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
        sec_dir = File.realpath("#{base_path}#{relative_path}")
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
    @secret_dir = base_path.gsub(File.realpath(@secrets_dir[dir_name]), '') unless relative_path.nil?
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
    decode_64 = YAML.safe_load(@yaml_content)
    @json_decode = decode_64.clone
    decode_64['data'].each do |key_plain, v_64|
      @json_decode['data'][key_plain] = Base64.decode64(v_64)
    end

    case @error
    when 1
      @message = {type: 'error', msg: "Can't descrypt file. Please check your permissions or your credential providers" }
    end
    slim :edit
  end

  post '/edit' do
    secret_dir, relative_path = params[:secret_file].split(':')
    base_path = @secrets_dir[secret_dir]['path']

    aws_profile = @secrets_dir[secret_dir]['aws_profile']
    kms_arn = @secrets_dir[secret_dir]['kms_arn']
    file_path = Helpers.real_path(base_path, relative_path)
    json_encode = YAML.safe_load(params['content'])
    encode_64 = json_encode.clone
    json_encode['data'].each do |key_plain, v_64|
      json_encode['data'][key_plain] = Base64.encode64(v_64)
    end

    tmp = Tempfile.new ['sops64', '.yml']
    tmp.write encode_64.to_yaml
    tmp.close
    new_content = %x(export AWS_PROFILE=#{aws_profile} && export SOPS_KMS_ARN=#{kms_arn} && sops -e #{tmp.path})
    File.write(file_path, new_content)
    redirect "/edit?secret_file=#{params[:secret_file]}"
  end

  get '/settings' do
    @json_content = YAML.safe_load(File.read(@path_config_file))
    slim :settings
  end

  get '/' do
    slim :index
  end
end
