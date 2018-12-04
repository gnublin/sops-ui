# MIT License
# Copyright (c) 2018 Gauthier FRANCOIS

require 'bundler/setup'
require 'sinatra'
require 'sinatra/base'

require 'tempfile'
require 'slim'
require 'yaml'
require 'find'

require 'sinatra/config_file'
require 'pry'
require 'hashdiff'
require 'base64'
require 'tempfile'

require_relative 'helpers.rb'
YAML_SAMPLE = '
---
apiVersion: v1
kind: Secret
metadata:
  namespace:
  name:
data:
'

class SopsUI < Sinatra::Application
  register Sinatra::ConfigFile
  set :root, File.dirname(__FILE__) + '/..'
  set :slim, layout: :_layout
  set :public_folder, 'node_modules'

  path_config_file = "config/#{ENV['RACK_ENV']}.yml"
  config_file path_config_file
  SOPS_CONFIG = settings.sops_config

  use Rack::Logger

  enable :sessions

  helpers do
    def logger
      request.logger
    end
  end
  Bundler.require

  before do
    @path_config_file = path_config_file
    @secrets_dir = SOPS_CONFIG['sops_folders']
    @message = session.delete(:message)
  end

  get '/view' do
    secrets_dir = {}
    if params[:dir]
      dir_name, relative_path = params[:dir].split(':')

      redirect '/' if dir_name.nil?

      base_path = File.realpath(@secrets_dir[dir_name]['path'])
      secrets_dir[dir_name] = {}

      begin
        sec_dir = File.realpath("#{base_path}/#{relative_path}")
        base_diff = sec_dir.gsub(base_path, '')
        base_path = base_diff == sec_dir ? nil : sec_dir
      rescue Errno::ENOENT
        redirect '/404'
      end

      if base_path.nil?
        session[:message] = {
          type: 'warning',
          msg: "Path #{params[:path]} not permit.Please check your permission or your configuration file.",
        }
        redirect "/view?path=#{dir_name}:" unless @secrets_dir[dir_name].nil?
        redirect '/404'
      end

      Dir.entries("#{base_path}/").each do |item|
        next if item.match?(/^\.$/)
        next if item.match?(/^\.\./) && relative_path.nil?
        next if item.match?(/^\.\./) && base_diff.empty?
        secrets_dir[dir_name][item] = File.directory?("#{base_path}/#{item}") ? 'dir' : 'file'
      end
      @secrets = secrets_dir
    else
      @error_message = 'Please specify a good dir'
    end
    @secret_dir = base_path.gsub(File.realpath(@secrets_dir[dir_name]['path']), '') unless relative_path.nil?
    slim :view
  end

  get '/edit' do
    secret_dir, relative_path = params[:secret_file].split(':')
    base_path = @secrets_dir[secret_dir]['path']

    file_path = Helpers.real_path(base_path, relative_path)
    redirect '/404' if file_path.nil?

    aws_profile = @secrets_dir[secret_dir]['aws_profile']
    @yaml_content = %x(export AWS_PROFILE=#{aws_profile} && sops -d #{file_path})
    @error = @yaml_content.empty? ? 1 : 0
    decode_64 =
      begin
        YAML.safe_load(@yaml_content)
      rescue Psych::SyntaxError
        @error = 2
      end

    case @error
    when 0
      @json_decode = decode_64.clone
      decode_64['data'].each do |key_plain, v_64|
        @json_decode['data'][key_plain] = Base64.decode64(v_64)
      end
    when 1
      @message =
        { type: 'error', msg: "Can't descrypt file. Please check your permissions or your credential providers" }
    when 2
      @message = { type: 'error', msg: "#{file_path} is not in YAML format" }
    end
    slim :edit
  end

  post '/edit' do
    secret_dir, relative_path = params[:secret_file].split(':')
    base_path = @secrets_dir[secret_dir]['path']

    aws_profile = @secrets_dir[secret_dir]['aws_profile']
    kms_arn = @secrets_dir[secret_dir]['kms_arn']
    file_path = Helpers.real_path(base_path, relative_path)

    @yaml_content = %x(export AWS_PROFILE=#{aws_profile} && sops -d #{file_path})
    @error = @yaml_content.empty? ? 1 : 0
    old_encoded_data = YAML.safe_load(@yaml_content)
    @error = 0
    json_encode =
      begin
        YAML.safe_load(params['content'])
      rescue Psych::SyntaxError
        @error = 1
      end

    if @error != 0
      session[:message] = {type: 'error', msg: 'Please respect the YAML format' }
      redirect request.referer
    end

    json_encode['data'].each do |key_plain, v_64|
      json_encode['data'][key_plain] = Base64.encode64(v_64.to_s)
    end

    res = nil
    diffs = HashDiff.diff(old_encoded_data, json_encode)
    diffs.each do |diff|
      case diff[0]
      when '~'
        to_change = diff[3]
      when '+'
        to_change = diff[2]
      when '-'
        to_change = ''
      end

      j_path_1, j_path_2 = diff[1].split('.')
      j_path = j_path_2.nil? ? "[\"#{j_path_1}\"]" : "[\"#{j_path_1}\"][\"#{j_path_2}\"]"
      to_rm = j_path_2 ? j_path_2 : j_path_1
      res =
        %x(export AWS_PROFILE=#{aws_profile} && export SOPS_KMS_ARN=#{kms_arn} &&\
          sops --set '#{j_path} #{to_change.dump}' #{file_path})
      %x(sed -i '/.*#{to_rm}:/d' #{file_path}) if to_change.empty?
    end

    redirect "/edit?secret_file=#{params[:secret_file]}"
  end

  post '/create_dir' do
    error = 0
    type = 'success'
    secret_dir, relative_path = params[:secret_path].split(':')
    base_path = @secrets_dir[secret_dir]['path']
    base_path = "#{base_path}/#{relative_path}" unless relative_path.nil?
    dir_name = "#{base_path}/#{params[:dir_name]}"

    if params[:dir_name].empty?
      error = 'Name is required'
      type = 'error'
    elsif File.exist?(dir_name)
      error = "Name #{params[:secret_dir]}/#{params[:dir_name]} already exist"
      type = 'error'
    end

    Dir.mkdir(dir_name) if error == 0
    error = "Dir #{params[:secret_dir]}/#{params[:dir_name]} has been  r ecreated" if error == 0

    session[:message] = {type: type, msg: error }
    redirect "/view?dir=#{params[:secret_dir]}"
  end

  get '/delete' do
    name, file_name = params[:name].split(':')
    file_path = @secrets_dir[name]['path']
    bag_file = "#{file_path}/#{file_name}"
    begin
      FileUtils.rm_r(bag_file)
      msg = "#{params[:bag_file]} has been deleted."
      type = 'success'
    rescue StandardError
      msg = "An error occured to delete #{file_name}"
      type = 'error'
    end
    session[:message] = {type: type, msg: msg}
    redirect "/view?dir=#{name}:#{file_name.split('/')[0...-1].join('/')}"
  end

  get '/create' do
    templates_dir = SOPS_CONFIG['templates_dir']
    @secret_used = SOPS_CONFIG['sops_folders'][params[:dir]]['aws_profile']
    @templates = {}
    @content = YAML.safe_load(YAML_SAMPLE)
    templates_dir&.each do |tpl_name, tpl_dir|
      Dir.entries(tpl_dir).each do |tpl_file|
        next if tpl_file.match?(/^\.$/)
        next if tpl_file.match?(/^\.\./)
        begin
          YAML.safe_load(File.read(File.realpath("#{tpl_dir}/#{tpl_file}")))
          is_yaml = 0
        rescue Psych::SyntaxError
          is_yaml = 1
        end
        if is_yaml == 0
          @templates[tpl_name] = [] unless @templates[tpl_name].is_a? Array
          @templates[tpl_name] << tpl_file
        end
      end
    end
    if params[:template]
      begin
        tpl_dir, tpl_name = params['template'].split(':')
        tpl_file = "#{SOPS_CONFIG['templates_dir'][tpl_dir]}/#{tpl_name}"
        read_file = File.read(tpl_file)
        begin
          @content = YAML.safe_load(read_file)
          @error = 0
        rescue Psych::SyntaxError
          @error = 1
          @message = {type: 'error', msg: 'Selected template is not in YAML format' }
        end
        @ser
      rescue Errno::ENOENT
        @error = 1
        @message = {type: 'error', msg: "Template #{params['tempalte']} not found" }
      end
    end
    slim :create
  end

  post '/create' do
    res = nil
    yaml_skelton = nil
    secret_dir, relative_path = params[:dir].split(':')
    base_path = @secrets_dir[secret_dir]['path']

    aws_profile = @secrets_dir[secret_dir]['aws_profile']
    kms_arn = @secrets_dir[secret_dir]['kms_arn']
    file_path = Helpers.real_path(base_path, relative_path)
    file_name = "#{file_path}/#{params[:file_name]}.yml"
    yaml_content = YAML.safe_load(params[:content])
    data_content = yaml_content.delete('data')
    yaml_content['data'] = {}
    data_content.map do |a, b|
      yaml_content['data'][a] = ''
      data_content[a] = Base64.encode64(b.to_s)
    end

    File.write(file_name, yaml_content.to_yaml)
    yaml_skelton = %x(export AWS_PROFILE=#{aws_profile} && sops -i -e -k #{kms_arn} #{file_name})
    data_content.each do |data_name, data_val|
      res =
        %x(export AWS_PROFILE=#{aws_profile} && export SOPS_KMS_ARN=#{kms_arn} &&\
          sops --set '["data"]["#{data_name}"] #{data_val.dump}' #{file_name})
    end
    redirect "/edit?secret_file=#{params[:dir]}:/#{params[:file_name]}.yml"
    raise 't'
  end

  get '/settings' do
    @json_content = YAML.safe_load(File.read(@path_config_file))
    slim :settings
  end

  get '/' do
    slim :index
  end
end
