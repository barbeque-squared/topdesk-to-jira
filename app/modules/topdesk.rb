require 'openssl'

require_relative 'topdesk/http_client'

module Topdesk
  class Client
  
    DEFAULT_OPTIONS = {
      :site               => 'http://localhost:8080',
      :context_path       => '/tas',
      :rest_base_path     => '/api',
      :ssl_verify_mode    => OpenSSL::SSL::VERIFY_PEER,
      :use_ssl            => true,
      :use_client_cert    => false,
      :auth_type          => :basic,
      :http_debug         => false
    }
    
    def initialize(options={})
      options = DEFAULT_OPTIONS.merge(options)
      @options = options
      @options[:rest_base_path] = @options[:context_path] + @options[:rest_base_path]
      
      case options[:auth_type]
      when :oauth, :oauth_2legged
        @request_client = OauthClient.new(@options)
        @consumer = @request_client.consumer
      when :basic
        @request_client = HttpClient.new(@options)
        @token = @request_client.make_login_request(:get, '/login/operator').body
        @options.delete(:username)
        @options.delete(:password)
      when :cookie
        raise ArgumentError, 'Options: :use_cookies must be true for :cookie authorization type' if @options.key?(:use_cookies) && !@options[:use_cookies]
        @options[:use_cookies] = true
        @request_client = HttpClient.new(@options)
        @request_client.make_cookie_auth_request
        @options.delete(:username)
        @options.delete(:password)
      else
        raise ArgumentError, 'Options: ":auth_type" must be ":oauth",":oauth_2legged", ":cookie" or ":basic"'
      end

      @http_debug = @options[:http_debug]

      @options.freeze

      @cache = OpenStruct.new
    end
    
    def incident(id)
      h = getUri("/incidents/id/#{id}")
      case h.code
      when '200'
        res = JSON.parse(h.body, object_class: OpenStruct)
        res.progresstrail = incident_progresstrail id
        res
      else
        raise "Invalid response code #{h.code}, msg=#{h.msg}, body=#{h.body}"
      end
    end
    
    def incident_progresstrail(id)
      res = []
      start = 0
      page_size = 100
      while true
        h = getUri("/incidents/id/#{id}/progresstrail", {start: start, page_size: page_size})
        case h.code
        when '200'
          # last page with at least one item
          res.concat(JSON.parse(h.body, object_class: OpenStruct))
          break
        when '204'
          # no things found, just break
          break
        when '206'
          # items found and there are more pages to do
          res.concat(JSON.parse(h.body, object_class: OpenStruct))
          start += page_size
        #~ when '403'
          #~ # todo: try to get a new login token, but raise an exception if this fails
        else
          raise "Invalid response code #{h.code}, msg=#{h.msg}, body=#{h.body}"
        end
      end
      res
    end
    
    # useful for attachments
    def rawUri(uri)
      uri = uri[8..-1] if uri.start_with? '/tas/api'
      getUriAcceptAll uri.gsub('/tas', '')
    end
    
    def incidents
      res = []
      start = 0
      page_size = 100
      while true
        h = getUri('/incidents', {start: start, page_size: page_size, order_by: 'creation_date+ASC'})
        case h.code
        when '200'
          # last page with at least one item
          res.concat(JSON.parse(h.body, object_class: OpenStruct))
          break
        when '204'
          # no things found, just break
          break
        when '206'
          # items found and there are more pages to do
          res.concat(JSON.parse(h.body, object_class: OpenStruct))
          start += page_size
        #~ when '403'
          #~ # todo: try to get a new login token, but raise an exception if this fails
        else
          raise "Invalid response code #{h.code}, msg=#{h.msg}, body=#{h.body}"
        end
      end
      res
    end
    
    def operator_current
      h = getUri("/operators/current")
      case h.code
      when '200'
        JSON.parse(h.body, object_class: OpenStruct)
      else
        raise "Invalid response code #{h.code}, msg=#{h.msg}, body=#{h.body}"
      end
    end
    
    def operator_groups(id)
      h = getUri("/operators/id/#{id}/operatorgroups")
      case h.code
      when '200'
        JSON.parse(h.body, object_class: OpenStruct)
      when '204'
        []
      else
        raise "Invalid response code #{h.code}, msg=#{h.msg}, body=#{h.body}"
      end
    end
    
    def permission_groups
      h = getUri("/permissiongroups")
      case h.code
      when '200'
        JSON.parse(h.body, object_class: OpenStruct)
      else
        raise "Invalid response code #{h.code}, msg=#{h.msg}, body=#{h.body}"
      end
    end
    
    def operator_filters_branch
      h = getUri("/operators/filters/branch")
      case h.code
      when '200'
        JSON.parse(h.body, object_class: OpenStruct)
      else
        raise "Invalid response code #{h.code}, msg=#{h.msg}, body=#{h.body}"
      end
    end
    
    def operator_filters_category
      h = getUri("/operators/filters/category")
      case h.code
      when '200'
        JSON.parse(h.body, object_class: OpenStruct)
      else
        raise "Invalid response code #{h.code}, msg=#{h.msg}, body=#{h.body}"
      end
    end
    
    def operator_filters_operator
      h = getUri("/operators/filters/operator")
      case h.code
      when '200'
        JSON.parse(h.body, object_class: OpenStruct)
      else
        raise "Invalid response code #{h.code}, msg=#{h.msg}, body=#{h.body}"
      end
    end
    
    private
    
    def getUri(uri, params=nil)
      raise "No token present" unless @token
      # no checking or escaping is done on parameters whatsoever
      uri += "?" + params.map{|e| e.join('=') }.join('&') if params
      h = @request_client.make_request(:get, uri, nil, {'Accept' => 'application/json', 'Authorization' => "TOKEN id=\"#{@token}\""})
      raise "Unauthorized (no token provided?)" if h.code == '401'
      raise "Forbidden (token expired?)" if h.code == '403'
      # if 403, login token expired?
      #~ raise "Expected 200, got #{h.code}. Body for debug: #{h.body}" unless h.code == '200'
      h
    end
    
    # useful for downloading attachments
    def getUriAcceptAll(uri, params=nil)
      raise "No token present" unless @token
      # no checking or escaping is done on parameters whatsoever
      uri += "?" + params.map{|e| e.join('=') }.join('&') if params
      h = @request_client.make_request(:get, uri, nil, {'Accept' => '*/*', 'Authorization' => "TOKEN id=\"#{@token}\""})
      raise "Unauthorized (no token provided?)" if h.code == '401'
      raise "Forbidden (token expired?)" if h.code == '403'
      # if 403, login token expired?
      #~ raise "Expected 200, got #{h.code}. Body for debug: #{h.body}" unless h.code == '200'
      h
    end
  end
end
