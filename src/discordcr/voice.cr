require "uri"

require "./mappings/gateway"
require "./mappings/vws"
require "./websocket"
require "./sodium"

module Discord
  class VoiceClient
    UDP_PROTOCOL = "udp"

    Log = Discord::Log.for("voice")

    # Supported encryption modes. Sorted by preference
    ENCRYPTION_MODES = {"xsalsa20_poly1305_lite", "xsalsa20_poly1305_suffix", "xsalsa20_poly1305"}

    OP_IDENTIFY            = 0
    OP_SELECT_PROTOCOL     = 1
    OP_READY               = 2
    OP_HEARTBEAT           = 3
    OP_SESSION_DESCRIPTION = 4
    OP_SPEAKING            = 5
    OP_HELLO               = 8

    @udp : VoiceUDP

    @sequence : UInt16 = 0_u16
    @time : UInt32 = 0_u32

    @endpoint : String
    @server_id : UInt64
    @user_id : UInt64
    @session_id : String
    @token : String

    @heartbeat_interval : Float32?
    @send_heartbeats = false

    # Creates a new voice client. The *payload* should be a payload received
    # from Discord as part of a VOICE_SERVER_UPDATE dispatch, received after
    # sending a voice state update (gateway op 4) packet. The *session* should
    # be the session currently in use by the gateway client on which the
    # aforementioned dispatch was received, and the *user_id* should be the
    # user ID of the account on which the voice client is created. (It is
    # received as part of the gateway READY dispatch, for example)
    def initialize(payload : Discord::Gateway::VoiceServerUpdatePayload,
                   session : Discord::Gateway::Session, user_id : UInt64 | Snowflake)
      initialize(payload.endpoint, payload.token, session.session_id, payload.guild_id, user_id)
    end

    # :nodoc:
    def initialize(@endpoint, @token, @session_id, guild_id : UInt64 | Snowflake, user_id : UInt64 | Snowflake)
      @user_id = user_id.to_u64
      host, port = @endpoint.split(':')

      @server_id = guild_id.to_u64

      @websocket = Discord::WebSocket.new(
        host: host,
        path: "/?v=4",
        port: port.to_i,
        tls: true
      )

      @websocket.on_message(&->on_message(Discord::WebSocket::Packet))
      @websocket.on_close(&->on_close(HTTP::WebSocket::CloseCode, String))

      @udp = VoiceUDP.new
    end

    # Initiates the connection process and blocks forever afterwards.
    def run
      @send_heartbeats = true
      spawn { heartbeat_loop }
      @websocket.run
    end

    # Closes the VWS connection, in effect disconnecting from voice.
    def close
      @send_heartbeats = false
      @websocket.close
    end

    # Sets the handler that should be run once the voice client has connected
    # successfully.
    def on_ready(&@ready_handler : ->)
    end

    # Sends a packet to indicate to Discord whether or not we are speaking
    # right now
    def send_speaking(speaking : Bool, delay : Int32 = 0)
      packet = VWS::SpeakingPacket.new(speaking, delay)
      @websocket.send(packet.to_json)
    end

    # Plays a single opus packet
    def play_opus(buf : Bytes)
      increment_packet_metadata
      @udp.send_audio(buf, @sequence, @time)
    end

    # Increment sequence and time
    private def increment_packet_metadata
      @sequence &+= 1
      @time &+= 960
    end

    private def heartbeat_loop
      while @send_heartbeats
        if @heartbeat_interval
          @websocket.send({op: 3, d: Time.utc.to_unix_ms}.to_json)
          sleep @heartbeat_interval.not_nil!.milliseconds
        else
          sleep 1
        end
      end
    end

    private def on_message(packet : Discord::WebSocket::Packet)
      Log.debug { "VWS packet received: #{packet} #{packet.data.to_s}" }

      case packet.opcode
      when OP_READY
        payload = VWS::ReadyPayload.from_json(packet.data)
        handle_ready(payload)
      when OP_SESSION_DESCRIPTION
        payload = VWS::SessionDescriptionPayload.from_json(packet.data)
        handle_session_description(payload)
      when OP_HELLO
        payload = VWS::HelloPayload.from_json(packet.data)
        handle_hello(payload)
      else
        # TODO: Debug log unknown opcodes?
      end
    end

    private def on_close(code : HTTP::WebSocket::CloseCode, message : String)
      @send_heartbeats = false
      reason = message.empty? ? "(none)" : message
      Log.warn { "VWS closed with code: #{code}, reason: #{reason}" }
    end

    private def handle_ready(payload : VWS::ReadyPayload)
      if selected_crypto = ENCRYPTION_MODES.find { |preferred| payload.modes.includes?(preferred) }
        udp_connect(payload.ip, payload.port.to_u32, payload.ssrc.to_u32, selected_crypto)
      else
        raise "No supported crypto modes found in #{payload.modes}"
      end
    end

    private def udp_connect(ip, port, ssrc, encryption_mode)
      @udp.connect(ip, port, ssrc)
      @udp.send_discovery
      ip, port = @udp.receive_discovery_reply
      send_select_protocol(UDP_PROTOCOL, ip, port, encryption_mode)
    end

    private def send_identify(server_id, user_id, session_id, token)
      packet = VWS::IdentifyPacket.new(server_id, user_id, session_id, token)
      @websocket.send(packet.to_json)
    end

    private def send_select_protocol(protocol, address, port, mode)
      data = VWS::ProtocolData.new(address, port, mode)
      packet = VWS::SelectProtocolPacket.new(protocol, data)
      @websocket.send(packet.to_json)
    end

    private def handle_session_description(payload : VWS::SessionDescriptionPayload)
      @udp.secret_key = Bytes.new(payload.secret_key.to_unsafe, payload.secret_key.size)
      @udp.mode = payload.mode

      # Once the secret key has been received, we are ready to send audio data.
      # Notify the user of this
      spawn { @ready_handler.try(&.call) }
    end

    private def handle_hello(payload : VWS::HelloPayload)
      @heartbeat_interval = payload.heartbeat_interval
      send_identify(@server_id, @user_id, @session_id, @token)
    end
  end

  # Client for Discord's voice UDP protocol, on which the actual audio data is
  # sent. There should be no reason to manually use this class: use
  # `VoiceClient` instead which uses this class internally.
  class VoiceUDP
    @secret_key : Bytes?
    @mode : String?
    @lite_nonce : UInt32 = 0

    property secret_key
    property mode
    getter socket

    def initialize
      @socket = UDPSocket.new
    end

    def connect(endpoint : String, port : UInt32, ssrc : UInt32)
      @ssrc = ssrc
      @socket.connect(endpoint, port)
    end

    # Sends a discovery packet to Discord, telling them that we want to know our
    # IP so we can select the protocol on the VWS
    def send_discovery
      data = Bytes.new(70)
      IO::ByteFormat::BigEndian.encode(@ssrc.not_nil!, data[0, 4])
      @socket.write(data)
    end

    # Awaits a response to the discovery request and returns our local IP and
    # port once the response is received
    def receive_discovery_reply : {String, UInt16}
      buf = Bytes.new(70)
      @socket.receive(buf)

      # The first four bytes are just the SSRC again, we don't care about that
      data = buf[4, buf.size - 4]
      ip = String.new(data[0, 64]).delete("\0")
      port = IO::ByteFormat::BigEndian.decode(UInt16, data[64, 2])

      {ip, port}
    end

    # Sends 20 ms of opus audio data to Discord, with the specified sequence and
    # time (used on the receiving client to synchronise packets)
    def send_audio(buf, sequence, time)
      header = create_header(sequence, time)
      nonce = create_nonce(header)
      buf = encrypt_audio(nonce, buf)

      new_buf = if @mode == "xsalsa20_poly1305"
                  Bytes.new(header.size + buf.size)
                else
                  Bytes.new(header.size + buf.size + nonce.size)
                end

      header.copy_to(new_buf)
      buf.copy_to(new_buf + header.size)

      nonce.copy_to(new_buf + header.size + buf.size) unless @mode == "xsalsa20_poly1305"

      @socket.write(new_buf)
    end

    # :nodoc:
    def create_header(sequence : UInt16, time : UInt32) : Bytes
      bytes = Bytes.new(12)

      # Write the magic bytes required by Discord
      bytes[0] = 0x80_u8
      bytes[1] = 0x78_u8

      IO::ByteFormat::BigEndian.encode(sequence, bytes[2, 2])
      IO::ByteFormat::BigEndian.encode(time, bytes[4, 4])
      IO::ByteFormat::BigEndian.encode(@ssrc.not_nil!, bytes[8, 4])

      bytes
    end

    private def create_nonce(header : Bytes)
      nonce = nil
      case @mode
      when "xsalsa20_poly1305"
        nonce = Bytes.new(header.size)
        header.copy_to(nonce)
      when "xsalsa20_poly1305_suffix"
        nonce = Random::Secure.random_bytes(24)
      when "xsalsa20_poly1305_lite"
        nonce = Bytes.new(4)
        IO::ByteFormat::BigEndian.encode(@lite_nonce, nonce)

        @lite_nonce &+= 1
      else
        raise "Cannot create a nonce for unsupported audio mode #{@mode.inspect}"
      end
      nonce
    end

    private def encrypt_audio(nonce : Bytes, buf : Bytes) : Bytes
      raise "No secret key was set!" unless @secret_key

      sodium_nonce = Bytes.new(24, 0_u8)
      nonce.copy_to(sodium_nonce)

      # Sodium constants
      zero_bytes = Sodium.crypto_secretbox_xsalsa20poly1305_zerobytes
      box_zero_bytes = Sodium.crypto_secretbox_xsalsa20poly1305_boxzerobytes

      # Prepend the buf with zero_bytes zero bytes
      message = Bytes.new(buf.size + zero_bytes, 0_u8)
      buf.copy_to(message + zero_bytes)

      # Create a buffer for the ciphertext
      c = Bytes.new(message.size)

      # Encrypt
      Sodium.crypto_secretbox_xsalsa20poly1305(c, message, message.bytesize, sodium_nonce, @secret_key.not_nil!)

      # The resulting ciphertext buffer has box_zero_bytes zero bytes prepended;
      # we don't want them in the result, so move the slice forward by that many
      # bytes
      c + box_zero_bytes
    end
  end

  # Utility function that runs the given block and measures the time it takes,
  # then sleeps the given time minus that time. This is useful for voice code
  # because (in most cases) voice data should be sent to Discord at a rate of
  # one frame every 20 ms, and if the processing and sending takes a certain
  # amount of time, then noticeable choppiness can be heard.
  def self.timed_run(total_time : Time::Span)
    delta = Time.measure { yield }

    sleep_time = {total_time - delta, Time::Span.zero}.max
    sleep sleep_time
  end

  # Runs the given block every *time_span*. This method takes into account the
  # execution time for the block to keep the intervals accurate.
  #
  # Note that if the block takes longer to execute than the given *time_span*,
  # there will be no delay: the next iteration follows immediately, with no
  # attempt to get in sync.
  def self.every(time_span : Time::Span)
    loop do
      timed_run(time_span) { yield }
    end
  end
end
