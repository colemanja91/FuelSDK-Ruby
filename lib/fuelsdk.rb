require "fuelsdk/version"

require 'rubygems'
require 'date'
require 'jwt'

module FuelSDK
  autoload :HTTPRequest, 'fuelsdk/http_request'
  autoload :Targeting, 'fuelsdk/targeting'
  autoload :Soap, 'fuelsdk/soap'
  autoload :Rest, 'fuelsdk/rest'
  require 'fuelsdk/client'
  require 'fuelsdk/objects'

  class ET_Constructor
    attr_accessor :status, :code, :message, :results, :request_id, :moreResults

    def initialize(response = nil, rest = false)
      @results = []
      if !response.nil? && !rest then
        @@body = response.body

        if ((!response.soap_fault?) or (!response.http_error?)) then
          @code = response.http.code
          @status = true
        elsif (response.soap_fault?) then
          @code = response.http.code
          @message = @@body[:fault][:faultstring]
          @status = false
        elsif (response.http_error?) then
          @code = response.http.code
          @status = false
        end
      elsif
        @code = response.code
        @status = true
        if @code != "200" then
          @status = false
        end

        begin
          @results = JSON.parse(response.body)
        rescue
          @message = response.body
        end

      end
    end
  end

  class ET_BaseObject
    attr_accessor :authStub, :props
    attr_reader :obj, :lastRequestID, :endpoint

    def initialize
      @authStub = nil
      @props = nil
      @filter = nil
      @lastRequestID = nil
      @endpoint = nil
    end
  end

  class ET_GetSupportRest < ET_BaseObject
    attr_reader :urlProps, :urlPropsRequired, :lastPageNumber

    def get(props = nil)
      if props and props.is_a? Hash then
        @props = props
      end

      completeURL = @endpoint
      additionalQS = {}

      if @props and @props.is_a? Hash then
        @props.each do |k,v|
          if @urlProps.include?(k) then
            completeURL.sub!("{#{k}}", v)
          else
            additionalQS[k] = v
          end
        end
      end

      @urlPropsRequired.each do |value|
        if !@props || !@props.has_key?(value) then
          raise "Unable to process request due to missing required prop: #{value}"
        end
      end

      @urlProps.each do |value|
        completeURL.sub!("/{#{value}}", "")
      end

      obj = ET_GetRest.new(@authStub, completeURL,additionalQS)

      if obj.results.has_key?('page') then
        @lastPageNumber = obj.results['page']
        pageSize = obj.results['pageSize']
        if obj.results.has_key?('count') then
          count = obj.results['count']
        elsif obj.results.has_key?('totalCount') then
          count = obj.results['totalCount']
        end

        if !count.nil? && count > (@lastPageNumber * pageSize)  then
          obj.moreResults = true
        end
      end
      return obj
    end

    def getMoreResults()
      if props and props.is_a? Hash then
        @props = props
      end

      originalPageValue = "1"
      removePageFromProps = false

      if !@props.nil? && @props.has_key?('$page') then
        originalPageValue = @props['page']
      else
        removePageFromProps = true
      end

      if @props.nil?
        @props = {}
      end

      @props['$page'] = @lastPageNumber + 1

      obj = self.get

      if removePageFromProps then
        @props.delete('$page')
      else
        @props['$page'] = originalPageValue
      end

      return obj
    end
  end

  class ET_CUDSupportRest < ET_GetSupportRest

    def post()
      completeURL = @endpoint

      if @props and @props.is_a? Hash then
        @props.each do |k,v|
          if @urlProps.include?(k) then
            completeURL.sub!("{#{k}}", v)
          end
        end
      end

      @urlPropsRequired.each do |value|
        if !@props || !@props.has_key?(value) then
          raise "Unable to process request due to missing required prop: #{value}"
        end
      end

      # Clean Optional Parameters from Endpoint URL first
      @urlProps.each do |value|
        completeURL.sub!("/{#{value}}", "")
      end

      ET_PostRest.new(@authStub, completeURL, @props)
    end

    def patch()
      completeURL = @endpoint
      # All URL Props are required when doing Patch
      @urlProps.each do |value|
        if !@props || !@props.has_key?(value) then
          raise "Unable to process request due to missing required prop: #{value}"
        end
      end

      if @props and @props.is_a? Hash then
        @props.each do |k,v|
          if @urlProps.include?(k) then
            completeURL.sub!("{#{k}}", v)
          end
        end
      end

      obj = ET_PatchRest.new(@authStub, completeURL, @props)
    end

    def delete()
      completeURL = @endpoint
      # All URL Props are required when doing Patch
      @urlProps.each do |value|
        if !@props || !@props.has_key?(value) then
          raise "Unable to process request due to missing required prop: #{value}"
        end
      end

      if @props and @props.is_a? Hash then
        @props.each do |k,v|
          if @urlProps.include?(k) then
            completeURL.sub!("{#{k}}", v)
          end
        end
      end

      ET_DeleteRest.new(@authStub, completeURL)
    end

  end


  class ET_GetRest < ET_Constructor
    def initialize(authStub, endpoint, qs = nil)
      authStub.refreshToken

      if qs then
        qs['access_token'] = authStub.authToken
      else
        qs = {"access_token" => authStub.authToken}
      end

      uri = URI.parse(endpoint)
      uri.query = URI.encode_www_form(qs)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      request = Net::HTTP::Get.new(uri.request_uri)
      requestResponse = http.request(request)

      @moreResults = false

      obj = super(requestResponse, true)
      return obj
    end
  end


  class ET_ContinueRest < ET_Constructor
    def initialize(authStub, endpoint, qs = nil)
      authStub.refreshToken

      if qs then
        qs['access_token'] = authStub.authToken
      else
        qs = {"access_token" => authStub.authToken}
      end

      uri = URI.parse(endpoint)
      uri.query = URI.encode_www_form(qs)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      request = Net::HTTP::Get.new(uri.request_uri)
      requestResponse = http.request(request)

      @moreResults = false

      super(requestResponse, true)
    end
  end


  class ET_PostRest < ET_Constructor
    def initialize(authStub, endpoint, payload)
      authStub.refreshToken

      qs = {"access_token" => authStub.authToken}
      uri = URI.parse(endpoint)
      uri.query = URI.encode_www_form(qs)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      request = Net::HTTP::Post.new(uri.request_uri)
      request.body =  payload.to_json
      request.add_field "Content-Type", "application/json"
      requestResponse = http.request(request)

      super(requestResponse, true)

    end
  end

  class ET_PatchRest < ET_Constructor
    def initialize(authStub, endpoint, payload)
      authStub.refreshToken

      qs = {"access_token" => authStub.authToken}
      uri = URI.parse(endpoint)
      uri.query = URI.encode_www_form(qs)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      request = Net::HTTP::Patch.new(uri.request_uri)
      request.body =  payload.to_json
      request.add_field "Content-Type", "application/json"
      requestResponse = http.request(request)
      super(requestResponse, true)

    end
  end

  class ET_DeleteRest < ET_Constructor
    def initialize(authStub, endpoint)
      authStub.refreshToken

      qs = {"access_token" => authStub.authToken}

      uri = URI.parse(endpoint)
      uri.query = URI.encode_www_form(qs)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      request = Net::HTTP::Delete.new(uri.request_uri)
      requestResponse = http.request(request)
      super(requestResponse, true)

    end
  end

  class ET_Campaign < ET_CUDSupportRest
    def initialize
      super
      @endpoint = 'https://www.exacttargetapis.com/hub/v1/campaigns/{id}'
      @urlProps = ["id"]
      @urlPropsRequired = []
    end

    class Asset < ET_CUDSupportRest
      def initialize
        super
        @endpoint = 'https://www.exacttargetapis.com/hub/v1/campaigns/{id}/assets/{assetId}'
        @urlProps = ["id", "assetId"]
        @urlPropsRequired = ["id"]
      end
    end
  end

  class ET_DataExtension < ET_CUDSupport
    attr_accessor :columns

    def initialize
      super
      @obj = 'DataExtension'
    end

    def post
      originalProps = @props

      if @props.is_a? Array then
        multiDE = []
        @props.each { |currentDE|
          currentDE['Fields'] = {}
          currentDE['Fields']['Field'] = []
          currentDE['columns'].each { |key|
            currentDE['Fields']['Field'].push(key)
          }
          currentDE.delete('columns')
          multiDE.push(currentDE.dup)
        }

        @props = multiDE
      else
        @props['Fields'] = {}
        @props['Fields']['Field'] = []

        @columns.each { |key|
        @props['Fields']['Field'].push(key)
        }
      end

      obj = super
      @props = originalProps
      return obj
    end

    def patch
      @props['Fields'] = {}
      @props['Fields']['Field'] = []
      @columns.each { |key|
        @props['Fields']['Field'].push(key)
      }
      obj = super
      @props.delete("Fields")
      return obj
    end

    class Column < ET_GetSupport
      def initialize
        super
        @obj = 'DataExtensionField'
      end

      def get

        if props and props.is_a? Array then
          @props = props
        end

        if @props and @props.is_a? Hash then
          @props = @props.keys
        end

        if filter and filter.is_a? Hash then
          @filter = filter
        end

        fixCustomerKey = false
        if filter and filter.is_a? Hash then
          @filter = filter
          if @filter.has_key?("Property") && @filter["Property"] == "CustomerKey" then
            @filter["Property"]  = "DataExtension.CustomerKey"
            fixCustomerKey = true
          end
        end

        obj = ET_Get.new(@authStub, @obj, @props, @filter)
        @lastRequestID = obj.request_id

        if fixCustomerKey then
          @filter["Property"] = "CustomerKey"
        end

        return obj
      end
    end

    class Row < ET_CUDSupport
      attr_accessor :Name, :CustomerKey

      def initialize()
        super
        @obj = "DataExtensionObject"
      end

      def get
        getName
        if props and props.is_a? Array then
          @props = props
        end

        if @props and @props.is_a? Hash then
          @props = @props.keys
        end

        if filter and filter.is_a? Hash then
          @filter = filter
        end

        obj = ET_Get.new(@authStub, "DataExtensionObject[#{@Name}]", @props, @filter)
        @lastRequestID = obj.request_id

        return obj
      end

      def post
        getCustomerKey
        originalProps = @props
        ## FIX THIS
        if @props.is_a? Array then
=begin
          multiRow = []
          @props.each { |currentDE|

            currentDE['columns'].each { |key|
              currentDE['Fields'] = {}
              currentDE['Fields']['Field'] = []
              currentDE['Fields']['Field'].push(key)
            }
            currentDE.delete('columns')
            multiRow.push(currentDE.dup)
          }

          @props = multiRow
=end
        else
          currentFields = []
          currentProp = {}

          @props.each { |key,value|
            currentFields.push({"Name" => key, "Value" => value})
          }
          currentProp['CustomerKey'] = @CustomerKey
          currentProp['Properties'] = {}
          currentProp['Properties']['Property'] = currentFields
        end

        obj = ET_Post.new(@authStub, @obj, currentProp)
        @props = originalProps
        obj
      end

      def patch
        getCustomerKey
        currentFields = []
        currentProp = {}

        @props.each { |key,value|
          currentFields.push({"Name" => key, "Value" => value})
        }
        currentProp['CustomerKey'] = @CustomerKey
        currentProp['Properties'] = {}
        currentProp['Properties']['Property'] = currentFields

        ET_Patch.new(@authStub, @obj, currentProp)
      end
      def delete
        getCustomerKey
        currentFields = []
        currentProp = {}

        @props.each { |key,value|
          currentFields.push({"Name" => key, "Value" => value})
        }
        currentProp['CustomerKey'] = @CustomerKey
        currentProp['Keys'] = {}
        currentProp['Keys']['Key'] = currentFields

        ET_Delete.new(@authStub, @obj, currentProp)
      end

      private
      def getCustomerKey
        if @CustomerKey.nil? then
          if @CustomerKey.nil? && @Name.nil? then
            raise 'Unable to process DataExtension::Row request due to CustomerKey and Name not being defined on ET_DatExtension::row'
          else
            de = ET_DataExtension.new
            de.authStub = @authStub
            de.props = ["Name","CustomerKey"]
            de.filter = {'Property' => 'CustomerKey','SimpleOperator' => 'equals','Value' => @Name}
            getResponse = de.get
            if getResponse.status && (getResponse.results.length == 1) then
              @CustomerKey = getResponse.results[0][:customer_key]
            else
              raise 'Unable to process DataExtension::Row request due to unable to find DataExtension based on Name'
            end
          end
        end
      end

      def getName
        if @Name.nil? then
          if @CustomerKey.nil? && @Name.nil? then
            raise 'Unable to process DataExtension::Row request due to CustomerKey and Name not being defined on ET_DatExtension::row'
          else
            de = ET_DataExtension.new
            de.authStub = @authStub
            de.props = ["Name","CustomerKey"]
            de.filter = {'Property' => 'CustomerKey','SimpleOperator' => 'equals','Value' => @CustomerKey}
            getResponse = de.get
            if getResponse.status && (getResponse.results.length == 1) then
              @Name = getResponse.results[0][:name]
            else
              raise 'Unable to process DataExtension::Row request due to unable to find DataExtension based on CustomerKey'
            end
          end
        end
      end
    end
  end

  class ET_TriggeredSend < ET_CUDSupport
    attr_accessor :subscribers
    def initialize
      super
      @obj = 'TriggeredSendDefinition'
    end

    def send
      @tscall = {"TriggeredSendDefinition" => @props, "Subscribers" => @subscribers}
      ET_Post.new(@authStub, "TriggeredSend", @tscall)
    end
  end

end
