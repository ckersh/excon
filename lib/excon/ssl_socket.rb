module Excon
  class SSLSocket < Socket

    def initialize(data = {})
      @data = data
      check_nonblock_support

      super

      # create ssl context
      ssl_context = OpenSSL::SSL::SSLContext.new

      if @data[:ssl_verify_peer]
        # turn verification on
        ssl_context.verify_mode = OpenSSL::SSL::VERIFY_PEER

        if @data[:ssl_ca_path]
          ssl_context.ca_path = @data[:ssl_ca_path]
        elsif @data[:ssl_ca_file]
          ssl_context.ca_file = @data[:ssl_ca_file]
        else # attempt default, fallback to bundled
          ssl_context.cert_store = OpenSSL::X509::Store.new
          if File.exists?(OpenSSL::Config::DEFAULT_CONFIG_FILE)
            ssl_context.cert_store.set_default_paths
          else
            ssl_context.cert_store.add_file(DEFAULT_CA_FILE)
          end
        end
      else
        # turn verification off
        ssl_context.verify_mode = OpenSSL::SSL::VERIFY_NONE
      end

      # maintain existing API
      certificate_path = @data[:client_cert] || @data[:certificate_path]
      private_key_path = @data[:client_key] || @data[:private_key_path]

      if certificate_path && private_key_path
        ssl_context.cert = OpenSSL::X509::Certificate.new(File.read(certificate_path))
        ssl_context.key = OpenSSL::PKey::RSA.new(File.read(private_key_path))
      elsif @data.has_key?(:certificate) && @data.has_key?(:private_key)
        ssl_context.cert = OpenSSL::X509::Certificate.new(@data[:certificate])
        ssl_context.key = OpenSSL::PKey::RSA.new(@data[:private_key])
      end

      if @data[:proxy]
        request = 'CONNECT ' << @data[:host] << ':' << @data[:port] << Excon::HTTP_1_1
        request << 'Host: ' << @data[:host] << ':' << @data[:port] << Excon::CR_NL

        if @data[:proxy][:password] || @data[:proxy][:user]
          auth = ['' << @data[:proxy][:user].to_s << ':' << @data[:proxy][:password].to_s].pack('m').delete(Excon::CR_NL)
          request << "Proxy-Authorization: Basic " << auth << Excon::CR_NL
        end

        request << 'Proxy-Connection: Keep-Alive' << Excon::CR_NL

        request << Excon::CR_NL

        # write out the proxy setup request
        @socket.write(request)

        # eat the proxy's connection response
        Excon::Response.parse(@socket, { :expects => 200, :method => "CONNECT" })
      end

      # convert Socket to OpenSSL::SSL::SSLSocket
      @socket = OpenSSL::SSL::SSLSocket.new(@socket, ssl_context)
      @socket.sync_close = true
      @socket.connect

      # Server Name Indication (SNI) RFC 3546
      if @socket.respond_to?(:hostname=)
        @socket.hostname = @data[:host]
      end

      # verify connection
      if @data[:ssl_verify_peer]
        @socket.post_connection_check(@data[:host])
      end

      @socket
    end

    def read(max_length=nil)
      check_nonblock_support
      super
    end

    def write(data)
      check_nonblock_support
      super
    end

    private

    def check_nonblock_support
      # backwards compatability for things lacking nonblock
      if !DEFAULT_NONBLOCK && @data[:nonblock]
        Excon.display_warning("Excon nonblock is not supported by your OpenSSL::SSL::SSLSocket")
        @data[:nonblock] = false
      end
    end

    def connect
      check_nonblock_support
      super
    end

  end
end
