require "http/client"
require "http/formdata"
require "openssl/ssl/context"
require "time/format"

require "./mappings/*"
require "./version"
require "./errors"

module Discord
  module REST
    SSL_CONTEXT = OpenSSL::SSL::Context::Client.new
    USER_AGENT  = "DiscordBot (https://github.com/discordcr/discordcr, #{Discord::VERSION})"
    API_BASE    = "https://discord.com/api/v9"

    Log = Discord::Log.for("rest")

    alias RateLimitKey = {route_key: Symbol, major_parameter: UInt64?}

    # Like `#request`, but does not do error checking beyond 429.
    def raw_request(route_key : Symbol, major_parameter : Snowflake | UInt64 | Nil, method : String, path : String, headers : HTTP::Headers, body : String?)
      mutexes = (@mutexes ||= Hash(RateLimitKey, Mutex).new)
      global_mutex = (@global_mutex ||= Mutex.new)

      headers["Authorization"] = @token
      headers["User-Agent"] = USER_AGENT
      headers["X-RateLimit-Precision"] = "millisecond"

      request_done = false
      rate_limit_key = {route_key: route_key, major_parameter: major_parameter.try(&.to_u64)}

      until request_done
        mutexes[rate_limit_key] ||= Mutex.new

        # Make sure to catch up with existing mutexes - they may be locked from
        # another fiber.
        mutexes[rate_limit_key].synchronize { }
        global_mutex.synchronize { }

        Log.info { "[HTTP OUT] #{method} #{path} (#{body.try &.size || 0} bytes)" }
        Log.debug { "[HTTP OUT] BODY: #{body}" }

        response = HTTP::Client.exec(method: method, url: API_BASE + path, headers: headers, body: body, tls: SSL_CONTEXT)

        Log.info { "[HTTP IN] #{response.status_code} #{response.status_message} (#{response.body.size} bytes)" }
        Log.debug { "[HTTP IN] BODY: #{response.body}" }

        if response.status_code == 429 || response.headers["X-RateLimit-Remaining"]? == "0"
          retry_after_value = response.headers["X-RateLimit-Reset-After"]? || response.headers["Retry-After"]?
          retry_after = retry_after_value.not_nil!.to_f

          if response.headers["X-RateLimit-Global"]?
            Log.warn { "Global rate limit exceeded! Pausing all requests for #{retry_after}" }
            global_mutex.synchronize { sleep retry_after }
          else
            Log.warn { "Pausing requests for #{rate_limit_key[:route_key]} in #{rate_limit_key[:major_parameter]} for #{retry_after}" }
            mutexes[rate_limit_key].synchronize { sleep retry_after }
          end

          # If we actually got a 429, i. e. the request failed, we need to
          # retry it.
          request_done = true unless response.status_code == 429
        else
          request_done = true
        end
      end

      response.not_nil!
    end

    # Makes a REST request to Discord, with the given *method* to the given
    # *path*, with the given *headers* set and with the given *body* being sent.
    # The *route_key* should uniquely identify the route used, for rate limiting
    # purposes. The *major_parameter* should be set to the guild or channel ID,
    # if either of those appears as the first parameter in the route.
    #
    # This method also does rate limit handling, so if a rate limit is
    # encountered, it may take longer than usual. (In case you're worried, this
    # won't block events from being processed.) It also performs other kinds
    # of error checking, so if a request fails (with a status code that is not
    # 429) you will be notified of that.
    def request(route_key : Symbol, major_parameter : Snowflake | UInt64 | Nil, method : String, path : String, headers : HTTP::Headers, body : String?)
      response = raw_request(route_key, major_parameter, method, path, headers, body)

      unless response.success?
        raise StatusException.new(response) unless response.content_type == "application/json"

        begin
          error = APIError.from_json(response.body)
        rescue
          raise StatusException.new(response)
        end
        raise CodeException.new(response, error)
      end

      response
    end

    # :nodoc:
    def encode_tuple(**tuple)
      JSON.build do |builder|
        builder.object do
          tuple.each do |key, value|
            next if value.nil?
            builder.field(key) { value.to_json(builder) }
          end
        end
      end
    end

    # Gets the gateway URL to connect to.
    #
    # [API docs for this method](https://discord.com/developers/docs/topics/gateway#get-gateway)
    def get_gateway
      response = request(
        :gateway,
        nil,
        "GET",
        "/gateway",
        HTTP::Headers.new,
        nil
      )

      GatewayResponse.from_json(response.body)
    end

    # Gets the gateway Bot URL to connect to, and the recommended amount of shards to make.
    #
    # [API docs for this method](https://discord.com/developers/docs/topics/gateway#get-gateway-bot)
    def get_gateway_bot
      response = request(
        :gateway_bot,
        nil,
        "GET",
        "/gateway/bot",
        HTTP::Headers.new,
        nil
      )

      GatewayBotResponse.from_json(response.body)
    end

    # Gets the OAuth2 application tied to a client.
    #
    # [API docs for this method](https://discord.com/developers/docs/topics/oauth2#get-current-application-information)
    def get_oauth2_application
      response = request(
        :ouath2_applications_me,
        nil,
        "GET",
        "/oauth2/applications/@me",
        HTTP::Headers.new,
        nil
      )

      OAuth2Application.from_json(response.body)
    end

    # Gets a channel by ID.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/channel#get-channel)
    def get_channel(channel_id : UInt64 | Snowflake)
      response = request(
        :channels_cid,
        channel_id,
        "GET",
        "/channels/#{channel_id}",
        HTTP::Headers.new,
        nil
      )

      Channel.from_json(response.body)
    end

    # Modifies a channel with new properties. Requires the "Manage Channel"
    # permission.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/channel#modify-channel)
    def modify_channel(channel_id : UInt64 | Snowflake, name : String? = nil, position : UInt32? = nil,
                       topic : String? = nil, bitrate : UInt32? = nil, user_limit : UInt32? = nil,
                       nsfw : Bool? = nil, rate_limit_per_user : Int32? = nil,
                       default_auto_archive_duration : AutoArchiveDuration? = nil, archived : Bool? = nil,
                       locked : Bool? = nil, invitable : Bool? = nil, video_quality_mode : VideoQualityMode? = nil,
                       rtc_region : String? = nil)
      json = encode_tuple(
        name: name,
        position: position,
        topic: topic,
        bitrate: bitrate,
        user_limit: user_limit,
        nsfw: nsfw,
        rate_limit_per_user: rate_limit_per_user,
        default_auto_archive_duration: default_auto_archive_duration,
        archived: archived,
        locked: locked,
        invitable: invitable,
        video_quality_mode: video_quality_mode,
        rtc_region: rtc_region,
      )

      response = request(
        :channels_cid,
        channel_id,
        "PATCH",
        "/channels/#{channel_id}",
        HTTP::Headers{"Content-Type" => "application/json"},
        json
      )

      Channel.from_json(response.body)
    end

    # Deletes a channel by ID. Requires the "Manage Channel" permission, or "Manage Threads" if the channel is a thread.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/channel#deleteclose-channel)
    def delete_channel(channel_id : UInt64 | Snowflake)
      request(
        :channels_cid,
        channel_id,
        "DELETE",
        "/channels/#{channel_id}",
        HTTP::Headers.new,
        nil
      )
    end

    # Gets a list of messages from the channel's history. Requires the "Read
    # Message History" permission.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/channel#get-channel-messages)
    def get_channel_messages(channel_id : UInt64 | Snowflake, limit : Int32 = 50, before : UInt64 | Snowflake | Nil = nil, after : UInt64 | Snowflake | Nil = nil, around : UInt64 | Snowflake | Nil = nil)
      path = "/channels/#{channel_id}/messages?limit=#{limit}"
      path += "&before=#{before}" if before
      path += "&after=#{after}" if after
      path += "&around=#{around}" if around

      response = request(
        :channels_cid_messages,
        channel_id,
        "GET",
        path,
        HTTP::Headers.new,
        nil
      )

      Array(Message).from_json(response.body)
    end

    # Returns a `Paginator` over a channel's message history. Requires the
    # "Read Message History" permission. See `get_channel_messages`.
    #
    # Will yield a channels message history in the given `direction` starting at
    # `start_id` until `limit` number of messages are observed, or the channel has
    # no further history. Setting `limit` to `nil` will have the paginator continue
    # to make requests until all messages are fetched in the given `direction`.
    def page_channel_messages(channel_id : UInt64 | Snowflake, start_id : UInt64 | Snowflake = 0_u64,
                              limit : Int32? = 100, direction : Paginator::Direction = Paginator::Direction::Down,
                              page_size : Int32 = 100)
      Paginator(Message).new(limit, direction ^ Paginator::Direction::Down) do |last_page|
        if direction.up?
          next_id = last_page.try &.last.id || start_id
          get_channel_messages(channel_id, page_size, before: next_id)
        else
          next_id = last_page.try &.first.id || start_id
          get_channel_messages(channel_id, page_size, after: next_id)
        end
      end
    end

    # Gets a single message from the channel's history. Requires the "Read
    # Message History" permission.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/channel#get-channel-message)
    def get_channel_message(channel_id : UInt64 | Snowflake, message_id : UInt64 | Snowflake)
      response = request(
        :channels_cid_messages_mid,
        channel_id,
        "GET",
        "/channels/#{channel_id}/messages/#{message_id}",
        HTTP::Headers.new,
        nil
      )

      Message.from_json(response.body)
    end

    # Sends a message to the channel. Requires the "Send Messages" permission.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/channel#create-message)
    #
    # The `embed` parameter can be used to append a rich embed to the message
    # which allows for displaying certain kinds of data in a more structured
    # way. An example:
    #
    # ```
    # embed = Discord::Embed.new(
    #   title: "Title of Embed",
    #   description: "Description of embed. This can be a long text. Neque porro quisquam est, qui dolorem ipsum, quia dolor sit, amet, consectetur, adipisci velit, sed quia non numquam eius modi tempora incidunt, ut labore et dolore magnam aliquam quaerat voluptatem.",
    #   timestamp: Time.utc,
    #   url: "https://example.com",
    #   image: Discord::EmbedImage.new(
    #     url: "https://example.com/image.png",
    #   ),
    #   fields: [
    #     Discord::EmbedField.new(
    #       name: "Name of Field",
    #       value: "Value of Field",
    #     ),
    #   ],
    # )
    #
    # client.create_message(channel_id, "The content of the message. This will display separately above the embed. This string can be empty.", embed)
    # ```
    #
    # For more details on the format of the `embed` object, look at the
    # [relevant documentation](https://discord.com/developers/docs/resources/channel#embed-object).
    def create_message(channel_id : UInt64 | Snowflake, content : String, embed : Embed? = nil, tts : Bool = false,
                       nonce : Int64 | String? = nil, allowed_mentions : AllowedMentions? = nil, message_reference : MessageReference? = nil)
      json = encode_tuple(
        content: content,
        embed: embed,
        tts: tts,
        nonce: nonce,
        allowed_mentions: allowed_mentions,
        message_reference: message_reference
      )

      response = request(
        :channels_cid_messages,
        channel_id,
        "POST",
        "/channels/#{channel_id}/messages",
        HTTP::Headers{"Content-Type" => "application/json"},
        json
      )

      Message.from_json(response.body)
    end

    # Start Thread from existing message
    # When called on a GUILD_TEXT channel, creates a GUILD_PUBLIC_THREAD.
    # When called on a GUILD_NEWS channel, creates a GUILD_NEWS_THREAD.
    # The id of the created thread will be the same as the id of the message, and as such a message can only have a single thread created from it.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/channel#start-thread-with-message)
    def start_thread(channel_id : UInt64 | Snowflake, message_id : UInt64 | Snowflake, name : String,
                     auto_archive_duration : AutoArchiveDuration, reason : String? = nil)
      json = encode_tuple(
        name: name,
        auto_archive_duration: auto_archive_duration
      )

      headers = HTTP::Headers{
        "Content-Type" => "application/json",
      }
      headers["X-Audit-Log-Reason"] = reason if reason

      response = request(
        :channels_cid_threads,
        channel_id,
        "POST",
        "/channels/#{channel_id}/messages/#{message_id}/threads",
        headers,
        json
      )

      Channel.from_json(response.body)
    end

    # Start Thread without Message
    # Creates a new thread that is not connected to an existing message.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/channel#start-thread-without-message)
    def start_thread(channel_id : UInt64 | Snowflake, name : String, auto_archive_duration : AutoArchiveDuration,
                     type : ChannelType? = ChannelType::GuildPublicThread, invitable : Bool? = nil, reason : String? = nil)
      json = encode_tuple(
        name: name,
        auto_archive_duration: auto_archive_duration,
        type: type,
        invitable: invitable
      )

      headers = HTTP::Headers{
        "Content-Type" => "application/json",
      }
      headers["X-Audit-Log-Reason"] = reason if reason

      response = request(
        :channels_cid_threads,
        channel_id,
        "POST",
        "/channels/#{channel_id}/threads",
        headers,
        json
      )

      Channel.from_json(response.body)
    end

    # Join Thread
    # Adds the current user to a thread. Also requires the thread is not archived.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/channel#join-thread)
    def join_thread(channel_id : UInt64 | Snowflake)
      request(
        :channels_cid_thread_members,
        channel_id,
        "PUT",
        "/channels/#{channel_id}/thread-members/@me",
        HTTP::Headers.new,
        nil
      )
    end

    # Add Thread Member
    # Adds another member to a thread. Requires the ability to send messages in the thread.
    # Also requires the thread is not archived.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/channel#add-thread-member)
    def add_thread_member(channel_id : UInt64 | Snowflake, user_id : UInt64 | Snowflake)
      request(
        :channels_cid_thread_members,
        channel_id,
        "PUT",
        "/channels/#{channel_id}/thread-members/#{user_id}",
        HTTP::Headers.new,
        nil
      )
    end

    # Leave Thread
    # Removes the current user from a thread. Also requires the thread is not archived.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/channel#leave-thread)
    def leave_thread(channel_id : UInt64 | Snowflake)
      request(
        :channels_cid_thread_members,
        channel_id,
        "DELETE",
        "/channels/#{channel_id}/thread-members/@me",
        HTTP::Headers.new,
        nil
      )
    end

    # Remove Thread Member
    # Removes another member from a thread. Requires the MANAGE_THREADS permission, or the creator of the thread if it is a GUILD_PRIVATE_THREAD.
    # Also requires the thread is not archived.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/channel#remove-thread-member)
    def remove_thread_member(channel_id : UInt64 | Snowflake, user_id : UInt64 | Snowflake)
      request(
        :channels_cid_thread_members,
        channel_id,
        "DELETE",
        "/channels/#{channel_id}/thread-members/#{user_id}",
        HTTP::Headers.new,
        nil
      )
    end

    # List Thread Members
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/channel#list-thread-members)
    def list_thread_members(channel_id : UInt64 | Snowflake)
      response = request(
        :channels_cid_thread_members,
        channel_id,
        "GET",
        "/channels/#{channel_id}/thread-members",
        HTTP::Headers.new,
        nil
      )

      Array(ThreadMember).from_json(response.body)
    end

    # List Active Threads
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/guild#list-active-threads)
    def list_active_threads(guild_id : UInt64 | Snowflake)
      response = request(
        :guild_gid_threads,
        guild_id,
        "GET",
        "/guilds/#{guild_id}/threads/active",
        HTTP::Headers.new,
        nil
      )

      ThreadsPayload.from_json(response.body)
    end

    # List Public Archived Threads
    # Returns archived threads in the channel that are public.
    # When called on a GUILD_TEXT channel, returns threads of type GUILD_PUBLIC_THREAD. When called on a GUILD_NEWS channel returns threads of type GUILD_NEWS_THREAD.
    # Threads are ordered by archive_timestamp, in descending order. Requires the READ_MESSAGE_HISTORY permission.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/channel#list-public-archived-threads)
    def list_public_archived_threads(channel_id : UInt64 | Snowflake, before : Time? = nil, limit : Int32? = nil)
      path = "/channels/#{channel_id}/threads/archived/public"
      path += "&before=#{before}" if before
      path += "&limit=#{limit}" if limit

      response = request(
        :channel_cid_threads,
        channel_id,
        "GET",
        path,
        HTTP::Headers.new,
        nil
      )

      ThreadsPayload.from_json(response.body)
    end

    # List Private Archived Threads
    # Returns archived threads in the channel that are of type GUILD_PRIVATE_THREAD.
    # Threads are ordered by archive_timestamp, in descending order.
    # Requires both the READ_MESSAGE_HISTORY and MANAGE_THREADS permissions.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/channel#list-private-archived-threads)
    def list_private_archived_threads(channel_id : UInt64 | Snowflake, before : Time? = nil, limit : Int32? = nil)
      path = "/channels/#{channel_id}/threads/archived/private"
      path += "&before=#{before}" if before
      path += "&limit=#{limit}" if limit

      response = request(
        :channel_cid_threads,
        channel_id,
        "GET",
        path,
        HTTP::Headers.new,
        nil
      )

      ThreadsPayload.from_json(response.body)
    end

    # List Joined Private Archived Threads
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/channel#list-joined-private-archived-threads)
    def list_joined_private_threads(channel_id : UInt64 | Snowflake, before : Time? = nil, limit : Int32? = nil)
      path = "/channels/#{channel_id}/users/@me/threads/archived/private"
      path += "&before=#{before}" if before
      path += "&limit=#{limit}" if limit

      response = request(
        :channel_cid_threads,
        channel_id,
        "GET",
        path,
        HTTP::Headers.new,
        nil
      )

      ThreadsPayload.from_json(response.body)
    end

    # Adds a reaction to a message. The `emoji` property must be in the format
    # `name:id` for custom emoji. For Unicode emoji it can simply be the UTF-8
    # encoded characters.
    # Requires the "Read Message History" permission and additionally
    # the "Add Reactions" permission if no one has reacted with this emoji yet.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/channel#create-reaction)
    def create_reaction(channel_id : UInt64 | Snowflake, message_id : UInt64 | Snowflake, emoji : String)
      response = request(
        :channels_cid_messages_mid_reactions_emoji_me,
        channel_id,
        "PUT",
        "/channels/#{channel_id}/messages/#{message_id}/reactions/#{URI.encode(emoji)}/@me",
        HTTP::Headers.new,
        nil
      )
    end

    # Removes the bot's own reaction from a message. The `emoji` property must
    # be in the format `name:id` for custom emoji. For unicode emoji it can
    # simply be the UTF-8 encoded characters.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/channel#delete-own-reaction)
    def delete_own_reaction(channel_id : UInt64 | Snowflake, message_id : UInt64 | Snowflake, emoji : String)
      request(
        :channels_cid_messages_mid_reactions_emoji_me,
        channel_id,
        "DELETE",
        "/channels/#{channel_id}/messages/#{message_id}/reactions/#{URI.encode(emoji)}/@me",
        HTTP::Headers.new,
        nil
      )
    end

    # Removes another user's reaction from a message. The `emoji` property must
    # be in the format `name:id` for custom emoji. For unicode emoji it can
    # simply be the UTF-8 encoded characters. Requires the "Manage Messages"
    # permission.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/channel#delete-user-reaction)
    def delete_user_reaction(channel_id : UInt64 | Snowflake, message_id : UInt64 | Snowflake, emoji : String, user_id : UInt64 | Snowflake)
      request(
        :channels_cid_messages_mid_reactions_emoji_uid,
        channel_id,
        "DELETE",
        "/channels/#{channel_id}/messages/#{message_id}/reactions/#{URI.encode(emoji)}/#{user_id}",
        HTTP::Headers.new,
        nil
      )
    end

    # Returns all users that have reacted with a specific emoji.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/channel#get-reactions)
    def get_reactions(channel_id : UInt64 | Snowflake, message_id : UInt64 | Snowflake, emoji : String)
      response = request(
        :channels_cid_messages_mid_reactions_emoji_me,
        channel_id,
        "GET",
        "/channels/#{channel_id}/messages/#{message_id}/reactions/#{URI.encode(emoji)}",
        HTTP::Headers.new,
        nil
      )

      Array(User).from_json(response.body)
    end

    # Removes all reactions from a message. Requires the "Manage Messages"
    # permission.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/channel#delete-all-reactions)
    def delete_all_reactions(channel_id : UInt64 | Snowflake, message_id : UInt64 | Snowflake)
      request(
        :channels_cid_messages_mid_reactions,
        channel_id,
        "DELETE",
        "/channels/#{channel_id}/messages/#{message_id}/reactions",
        HTTP::Headers.new,
        nil
      )
    end

    # Removes all reactions for a given emoji from a message. Requires the "Manage Messages"
    # permission.
    #
    # [API Docs for this method]()
    def delete_reaction(channel_id : UInt64 | Snowflake, message_id : UInt64 | Snowflake, emoji : String)
      request(
        :channels_cid_messages_mid_reactions_emoji,
        channel_id,
        "DELETE",
        "/channels/#{channel_id}/messages/#{message_id}/reactions/#{URI.encode(emoji)}",
        HTTP::Headers.new,
        nil
      )
    end

    # Uploads a file to a channel. Requires the "Send Messages" and "Attach
    # Files" permissions.
    #
    # If the specified `file` is a `File` object and no filename is specified,
    # the file's filename will be used instead. If it is an `IO` without
    # filename information, Discord will generate a placeholder filename.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/channel#create-message)
    # (same as `#create_message` -- this method implements form data bodies
    # while `#create_message` implements JSON bodies)
    def upload_file(channel_id : UInt64 | Snowflake, content : String?, file : IO, filename : String? = nil,
                    embed : Embed? = nil, allowed_mentions : AllowedMentions? = nil, spoiler : Bool = false)
      io = IO::Memory.new

      unless filename
        if file.is_a? File
          filename = File.basename(file.path)
        else
          filename = ""
        end
      end

      if spoiler && !filename.starts_with?("SPOILER_")
        filename = "SPOILER_" + filename
      end

      builder = HTTP::FormData::Builder.new(io)
      builder.file("file", file, HTTP::FormData::FileMetadata.new(filename: filename))
      if content || embed
        json = encode_tuple(
          content: content,
          embed: embed,
          allowed_mentions: allowed_mentions
        )
        builder.field("payload_json", json)
      end
      builder.finish

      response = request(
        :channels_cid_messages,
        channel_id,
        "POST",
        "/channels/#{channel_id}/messages",
        HTTP::Headers{"Content-Type" => builder.content_type},
        io.to_s
      )

      Message.from_json(response.body)
    end

    # Edits an existing message on the channel. This only works for messages
    # sent by the bot itself - you can't edit others' messages.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/channel#edit-message)
    def edit_message(channel_id : UInt64 | Snowflake, message_id : UInt64 | Snowflake, content : String, embed : Embed? = nil)
      response = request(
        :channels_cid_messages_mid,
        channel_id,
        "PATCH",
        "/channels/#{channel_id}/messages/#{message_id}",
        HTTP::Headers{"Content-Type" => "application/json"},
        {content: content, embed: embed}.to_json
      )

      Message.from_json(response.body)
    end

    # Deletes a message from the channel. Requires the message to either have
    # been sent by the bot itself or the bot to have the "Manage Messages"
    # permission.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/channel#delete-message)
    def delete_message(channel_id : UInt64 | Snowflake, message_id : UInt64 | Snowflake)
      response = request(
        :channels_cid_messages_mid,
        channel_id,
        "DELETE",
        "/channels/#{channel_id}/messages/#{message_id}",
        HTTP::Headers.new,
        nil
      )
    end

    # Deletes multiple messages at once from the channel. The maximum amount is
    # 100 messages, the minimum is 2. Requires the "Manage Messages" permission.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/channel#bulk-delete-messages)
    def bulk_delete_messages(channel_id : UInt64 | Snowflake, message_ids : Array(UInt64 | Snowflake))
      response = request(
        :channels_cid_messages_bulk_delete,
        channel_id,
        "POST",
        "/channels/#{channel_id}/messages/bulk-delete",
        HTTP::Headers{"Content-Type" => "application/json"},
        {messages: message_ids}.to_json
      )
    end

    # Edits an existing permission overwrite on a channel with new permissions,
    # or creates a new one. The *overwrite_id* should be either a user or a role
    # ID. Requires the "Manage Roles" permission.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/channel#edit-channel-permissions)
    def edit_channel_permissions(channel_id : UInt64 | Snowflake, overwrite_id : UInt64 | Snowflake,
                                 type : String, allow : Permissions, deny : Permissions)
      json = encode_tuple(
        allow: allow,
        deny: deny,
        type: type
      )

      response = request(
        :channels_cid_permissions_oid,
        channel_id,
        "PUT",
        "/channels/#{channel_id}/permissions/#{overwrite_id}",
        HTTP::Headers{"Content-Type" => "application/json"},
        json
      )
    end

    # Gets a list of invites for this channel. Requires the "Manage Channel"
    # permission.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/channel#get-channel-invites)
    def get_channel_invites(channel_id : UInt64 | Snowflake)
      response = request(
        :channels_cid_invites,
        channel_id,
        "GET",
        "/channels/#{channel_id}/invites",
        HTTP::Headers.new,
        nil
      )

      Array(InviteMetadata).from_json(response.body)
    end

    # Creates a new invite for the channel. Requires the "Create Instant Invite"
    # permission.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/channel#create-channel-invite)
    def create_channel_invite(channel_id : UInt64 | Snowflake, max_age : UInt32 = 0_u32,
                              max_uses : UInt32 = 0_u32, temporary : Bool = false)
      json = encode_tuple(
        max_age: max_age,
        max_uses: max_uses,
        temporary: temporary
      )

      response = request(
        :channels_cid_invites,
        channel_id,
        "POST",
        "/channels/#{channel_id}/invites",
        HTTP::Headers{"Content-Type" => "application/json"},
        json
      )

      Invite.from_json(response.body)
    end

    # Deletes a permission overwrite from a channel. Requires the "Manage
    # Permissions" permission.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/channel#delete-channel-permission)
    def delete_channel_permission(channel_id : UInt64 | Snowflake, overwrite_id : UInt64 | Snowflake)
      response = request(
        :channels_cid_permissions_oid,
        channel_id,
        "DELETE",
        "/channels/#{channel_id}/permissions/#{overwrite_id}",
        HTTP::Headers.new,
        nil
      )
    end

    # Causes the bot to appear as typing on the channel. This generally lasts
    # 10 seconds, but should be refreshed every five seconds. Requires the
    # "Send Messages" permission.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/channel#trigger-typing-indicator)
    def trigger_typing_indicator(channel_id : UInt64 | Snowflake)
      response = request(
        :channels_cid_typing,
        channel_id,
        "POST",
        "/channels/#{channel_id}/typing",
        HTTP::Headers.new,
        nil
      )
    end

    # Get a list of messages pinned to this channel.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/channel#get-pinned-messages)
    def get_pinned_messages(channel_id : UInt64 | Snowflake)
      response = request(
        :channels_cid_pins,
        channel_id,
        "GET",
        "/channels/#{channel_id}/pins",
        HTTP::Headers.new,
        nil
      )

      Array(Message).from_json(response.body)
    end

    # Pins a new message to this channel. Requires the "Manage Messages"
    # permission.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/channel#add-pinned-channel-message)
    def add_pinned_channel_message(channel_id : UInt64 | Snowflake, message_id : UInt64 | Snowflake)
      response = request(
        :channels_cid_pins_mid,
        channel_id,
        "PUT",
        "/channels/#{channel_id}/pins/#{message_id}",
        HTTP::Headers.new,
        nil
      )
    end

    # Unpins a message from this channel. Requires the "Manage Messages"
    # permission.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/channel#delete-pinned-channel-message)
    def delete_pinned_channel_message(channel_id : UInt64 | Snowflake, message_id : UInt64 | Snowflake)
      response = request(
        :channels_cid_pins_mid,
        channel_id,
        "DELETE",
        "/channels/#{channel_id}/pins/#{message_id}",
        HTTP::Headers.new,
        nil
      )
    end

    # Gets a guild by ID.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/guild#get-guild)
    def get_guild(guild_id : UInt64 | Snowflake)
      response = request(
        :guilds_gid,
        guild_id,
        "GET",
        "/guilds/#{guild_id}",
        HTTP::Headers.new,
        nil
      )

      Guild.from_json(response.body)
    end

    # Modifies an existing guild with new properties. Requires the "Manage
    # Server" permission.
    # NOTE: To remove a guild's icon, you can send an empty string for the `icon` argument.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/guild#modify-guild)
    def modify_guild(guild_id : UInt64 | Snowflake, name : String? = nil, region : String? = nil,
                     verification_level : UInt8? = nil, afk_channel_id : UInt64 | Snowflake | Nil = nil,
                     afk_timeout : Int32? = nil, icon : String? = nil, owner_id : UInt64 | Snowflake | Nil = nil,
                     splash : String? = nil, reason : String? = nil)
      json = encode_tuple(
        name: name,
        region: region,
        verification_level: verification_level,
        afk_channel_id: afk_channel_id,
        afk_timeout: afk_timeout,
        icon: icon,
        owner_id: owner_id,
        splash: splash
      )

      headers = HTTP::Headers{
        "Content-Type" => "application/json",
      }
      headers["X-Audit-Log-Reason"] = reason if reason

      response = request(
        :guilds_gid,
        guild_id,
        "PATCH",
        "/guilds/#{guild_id}",
        headers,
        json
      )

      Guild.from_json(response.body)
    end

    # Deletes a guild. Requires the bot to be the server owner.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/guild#delete-guild)
    def delete_guild(guild_id : UInt64 | Snowflake)
      response = request(
        :guilds_gid,
        guild_id,
        "DELETE",
        "/guilds/#{guild_id}",
        HTTP::Headers.new,
        nil
      )

      Guild.from_json(response.body)
    end

    # Gets a list of emoji on the guild.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/emoji#list-guild-emojis)
    def list_guild_emojis(guild_id : UInt64 | Snowflake)
      response = request(
        :guilds_gid_emojis,
        guild_id,
        "GET",
        "/guilds/#{guild_id}/emojis",
        HTTP::Headers.new,
        nil
      )

      Array(Emoji).from_json(response.body)
    end

    # Gets a specific emoji by guild ID and emoji ID.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/emoji#get-guild-emoji)
    def get_guild_emoji(guild_id : UInt64 | Snowflake, emoji_id : UInt64 | Snowflake)
      response = request(
        :guilds_gid_emojis_eid,
        guild_id,
        "GET",
        "/guilds/#{guild_id}/emojis/#{emoji_id}",
        HTTP::Headers.new,
        nil
      )

      Emoji.from_json(response.body)
    end

    # Modifies a guild emoji. Requires the "Manage Emojis" permission.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/emoji#modify-guild-emoji)
    def modify_guild_emoji(guild_id : UInt64 | Snowflake, emoji_id : UInt64 | Snowflake, name : String)
      response = request(
        :guilds_gid_emojis_eid,
        guild_id,
        "PATCH",
        "/guilds/#{guild_id}/emojis/#{emoji_id}",
        HTTP::Headers{"Content-Type" => "application/json"},
        {name: name}.to_json
      )

      Emoji.from_json(response.body)
    end

    # Creates a guild emoji. Requires the "Manage Emojis" permission.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/emoji#create-guild-emoji)
    def create_guild_emoji(guild_id : UInt64 | Snowflake, name : String, image : String)
      json = encode_tuple(
        name: name,
        image: image,
      )

      response = request(
        :guilds_gid_emojis,
        guild_id,
        "POST",
        "/guilds/#{guild_id}/emojis",
        HTTP::Headers{"Content-Type" => "application/json"},
        json
      )

      Emoji.from_json(response.body)
    end

    # Deletes a guild emoji. Requires the "Manage Emojis" permission.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/emoji#delete-guild-emoji)
    def delete_guild_emoji(guild_id : UInt64 | Snowflake, emoji_id : UInt64 | Snowflake)
      request(
        :guilds_gid_emojis_eid,
        guild_id,
        "DELETE",
        "/guilds/#{guild_id}/emojis/#{emoji_id}",
        HTTP::Headers.new,
        nil
      )
    end

    # Gets a list of channels in a guild.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/guild#get-guild-channels)
    def get_guild_channels(guild_id : UInt64 | Snowflake)
      response = request(
        :guilds_gid_channels,
        guild_id,
        "GET",
        "/guilds/#{guild_id}/channels",
        HTTP::Headers.new,
        nil
      )

      Array(Channel).from_json(response.body)
    end

    # Creates a new channel on this guild. Requires the "Manage Channels"
    # permission.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/guild#create-guild-channel)
    def create_guild_channel(guild_id : UInt64 | Snowflake, name : String, type : ChannelType, topic : String? = nil,
                             bitrate : UInt32? = nil, user_limit : UInt32? = nil, rate_limit_per_user : Int32? = nil,
                             position : UInt32? = nil, parent_id : UInt64? | Snowflake? = nil, nsfw : Bool? = nil,
                             reason : String? = nil)
      json = encode_tuple(
        name: name,
        type: type,
        topic: topic,
        bitrate: bitrate,
        user_limit: user_limit,
        rate_limit_per_user: rate_limit_per_user,
        position: position,
        parent_id: parent_id,
        nsfw: nsfw
      )

      headers = HTTP::Headers{
        "Content-Type" => "application/json",
      }
      headers["X-Audit-Log-Reason"] = reason if reason

      response = request(
        :guilds_gid_channels,
        guild_id,
        "POST",
        "/guilds/#{guild_id}/channels",
        headers,
        json
      )

      Channel.from_json(response.body)
    end

    # Creates a new Stage instance associated to a Stage channel.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/stage-instance#create-stage-instance)
    def create_stage_instance(channel_id : UInt64 | Snowflake, topic : String, privacy_level : StagePrivacyLevel = StagePrivacyLevel::GUILD_ONLY)
      json = encode_tuple(
        channel_id: channel_id,
        topic: topic,
        privacy_level: privacy_level
      )

      response = request(
        :stage_instances_cid,
        channel_id,
        "POST",
        "/stage-instances",
        HTTP::Headers{"Content-Type" => "application/json"},
        json
      )

      StageInstance.from_json(response.body)
    end

    # Gets the Stage instance associated with the passed Stage channel if it exists.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/stage-instance#get-stage-instance)
    def get_stage_instance(channel_id : UInt64 | Snowflake)
      response = request(
        :stage_instances_cid,
        channel_id,
        "GET",
        "/stage-instances/#{channel_id}",
        HTTP::Headers.new,
        nil
      )

      StageInstance.from_json(response.body)
    end

    # Updates fields of an existing Stage instance.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/stage-instance#update-stage-instance)
    def update_stage_instance(channel_id : UInt64 | Snowflake, topic : String? = nil, privacy_level : StagePrivacyLevel? = nil)
      json = encode_tuple(
        topic: topic,
        privacy_level: privacy_level
      )

      response = request(
        :stage_instances_cid,
        channel_id,
        "PATCH",
        "/stage-instances/#{channel_id}",
        HTTP::Headers{"Content-Type" => "application/json"},
        json
      )

      StageInstance.from_json(response.body)
    end

    # Deletes the Stage instance associated with the passed Stage channel.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/stage-instance#delete-stage-instance)
    def delete_stage_instance(channel_id : UInt64 | Snowflake)
      request(
        :stage_instances_cid,
        channel_id,
        "DELETE",
        "/stage-instances/#{channel_id}",
        HTTP::Headers.new,
        nil
      )
    end

    # Gets the vanity URL of a guild. Requires the guild to be partnered.
    #
    # There are no API docs for this method.
    def get_guild_vanity_url(guild_id : UInt64 | Snowflake)
      response = request(
        :guilds_gid_vanityurl,
        guild_id,
        "GET",
        "/guilds/#{guild_id}/vanity-url",
        HTTP::Headers.new,
        nil
      )

      GuildVanityURLResponse.from_json(response.body).code
    end

    # Sets the vanity URL on this guild. Requires the guild to be
    # partnered.
    #
    # There are no API docs for this method.
    def modify_guild_vanity_url(guild_id : UInt64 | Snowflake, code : String)
      request(
        :guilds_gid_vanityurl,
        guild_id,
        "PATCH",
        "/guilds/#{guild_id}/vanity-url",
        HTTP::Headers{"Content-Type" => "application/json"},
        {code: code}.to_json
      )
    end

    # Updates the current user's, or passed user's voice state.
    # For use with Stage Channels only.
    # The user that is being updated must be inside of the stage channel.
    # Requires "MUTE_MEMBERS" to (un)suppress other members, you can always suppress yourself.
    # Requires "REQUEST_TO_SPEAK" to request to speak.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/guild#update-current-user-voice-state)
    def modify_voice_state(guild_id : UInt64 | Snowflake,
                           channel_id : UInt64 | Snowflake,
                           user_id : UInt64 | Snowflake | Nil = nil,
                           suppress : Bool? = nil,
                           request_to_speak_timestamp : Time? = nil)
      json = encode_tuple(
        channel_id: channel_id,
        suppress: suppress,
        request_to_speak_timestamp: request_to_speak_timestamp,
      )

      request(
        :guilds_gid_voicestate,
        guild_id,
        "PATCH",
        "/guilds/#{guild_id}/voice-states/#{user_id || "@me"}",
        HTTP::Headers{"Content-Type" => "application/json"},
        json
      )
    end

    # Modifies the position of channels within a guild. Requires the
    # "Manage Channels" permission.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/guild#modify-guild-channel-positions)
    def modify_guild_channel_positions(guild_id : UInt64 | Snowflake,
                                       positions : Array(ModifyChannelPositionPayload))
      request(
        :guilds_gid_channels,
        guild_id,
        "PATCH",
        "/guilds/#{guild_id}/channels",
        HTTP::Headers{"Content-Type" => "application/json"},
        positions.to_json
      )
    end

    # Gets a specific member by both IDs.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/guild#get-guild-member)
    def get_guild_member(guild_id : UInt64 | Snowflake, user_id : UInt64 | Snowflake)
      response = request(
        :guilds_gid_members_uid,
        guild_id,
        "GET",
        "/guilds/#{guild_id}/members/#{user_id}",
        HTTP::Headers.new,
        nil
      )

      GuildMember.from_json(response.body)
    end

    # Gets multiple guild members at once. The *limit* can be at most 1000.
    # The resulting list will be sorted by user IDs, use the *after* parameter
    # to specify what ID to start at.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/guild#list-guild-members)
    def list_guild_members(guild_id : UInt64 | Snowflake, limit : Int32 = 1000, after : UInt64 | Snowflake = 0_u64)
      path = "/guilds/#{guild_id}/members?limit=#{limit}&after=#{after}"

      response = request(
        :guilds_gid_members,
        guild_id,
        "GET",
        path,
        HTTP::Headers.new,
        nil
      )

      Array(GuildMember).from_json(response.body)
    end

    # Returns a `Paginator` over the given guilds members.
    #
    # Will yield members starting at `start_id` until  `limit` number of members
    # guilds are observed, or the user has no further guilds. Setting `limit`
    # to `nil` will have the paginator continue to make requests until all members
    # are fetched.
    def page_guild_members(guild_id : UInt64 | Snowflake, start_id : UInt64 | Snowflake = 0_u64,
                           limit : Int32? = 1000, page_size : Int32 = 1000)
      Paginator(GuildMember).new(limit, Paginator::Direction::Down) do |last_page|
        next_id = last_page.try &.last.user.id || start_id
        list_guild_members(guild_id, page_size, next_id)
      end
    end

    # Adds a user to the guild, provided you have a valid OAuth2 access token
    # for the user with the `guilds.join` scope.
    #
    # NOTE: The bot must be a member of the target guild, and have permissions
    #   to create instant invites.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/guild#add-guild-member)
    def add_guild_member(guild_id : UInt64, user_id : UInt64,
                         access_token : String, nick : String? = nil,
                         roles : Array(UInt64)? = nil, mute : Bool? = nil,
                         deaf : Bool? = nil)
      json = encode_tuple(
        access_token: access_token,
        nick: nick,
        roles: roles,
        mute: mute,
        deaf: deaf
      )

      response = request(
        :guilds_gid_members_uid,
        guild_id,
        "PUT",
        "/guilds/#{guild_id}/members/#{user_id}",
        HTTP::Headers{"Content-Type" => "application/json"},
        json
      )

      if response.status_code == 201
        GuildMember.from_json(response.body)
      else
        nil
      end
    end

    # Changes a specific member's properties. Requires:
    #
    #  - the "Manage Roles" permission and the role to change to be lower
    #    than the bot's highest role if changing the roles,
    #  - the "Manage Nicknames" permission when changing the nickname,
    #  - the "Mute Members" permission when changing mute status,
    #  - the "Deafen Members" permission when changing deaf status,
    #  - and the "Move Members" permission as well as the "Connect" permission
    #    to the new channel when changing voice channel ID.
    #
    # NOTE: To remove a member's nickname, you can send an empty string for the `nick` argument.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/guild#modify-guild-member)
    def modify_guild_member(guild_id : UInt64 | Snowflake, user_id : UInt64 | Snowflake, nick : String? = nil,
                            roles : Array(UInt64 | Snowflake)? = nil, mute : Bool? = nil, deaf : Bool? = nil,
                            channel_id : UInt64 | Snowflake | Nil = nil, reason : String? = nil)
      json = encode_tuple(
        nick: nick,
        roles: roles,
        mute: mute,
        deaf: deaf,
        channel_id: channel_id
      )

      headers = HTTP::Headers{
        "Content-Type" => "application/json",
      }
      headers["X-Audit-Log-Reason"] = reason if reason

      request(
        :guilds_gid_members_uid,
        guild_id,
        "PATCH",
        "/guilds/#{guild_id}/members/#{user_id}",
        headers,
        json
      )
    end

    # Modifies the nickname of the current user in a guild.
    #
    # NOTE: To remove a nickname, you can send an empty string for the `nick` argument.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/guild#modify-current-user-nick)
    def modify_current_user_nick(guild_id : UInt64, nick : String)
      request(
        :guilds_gid_members_me,
        guild_id,
        "PATCH",
        "/guilds/#{guild_id}/members/@me/nick",
        HTTP::Headers{"Content-Type" => "application/json"},
        {nick: nick}.to_json
      )
    end

    # Kicks a member from the server. Requires the "Kick Members" permission.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/guild#remove-guild-member)
    def remove_guild_member(guild_id : UInt64 | Snowflake, user_id : UInt64 | Snowflake, reason : String? = nil)
      headers = HTTP::Headers.new
      headers["X-Audit-Log-Reason"] = reason if reason

      request(
        :guilds_gid_members_uid,
        guild_id,
        "DELETE",
        "/guilds/#{guild_id}/members/#{user_id}",
        headers,
        nil
      )
    end

    # Adds a role to a member. Requires the "Manage Roles" permission.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/guild#add-guild-member-role)
    def add_guild_member_role(guild_id : UInt64 | Snowflake, user_id : UInt64 | Snowflake, role_id : UInt64 | Snowflake)
      request(
        :guilds_gid_members_uid_roles_rid,
        guild_id,
        "PUT",
        "/guilds/#{guild_id}/members/#{user_id}/roles/#{role_id}",
        HTTP::Headers.new,
        nil
      )
    end

    # Removes a role from a member. Requires the "Manage Roles" permission.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/guild#remove-guild-member-role)
    def remove_guild_member_role(guild_id : UInt64, user_id : UInt64, role_id : UInt64)
      request(
        :guilds_gid_members_uid_roles_rid,
        guild_id,
        "DELETE",
        "/guilds/#{guild_id}/members/#{user_id}/roles/#{role_id}",
        HTTP::Headers.new,
        nil
      )
    end

    # Gets a list of members banned from this server. Requires the "Ban Members"
    # permission.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/guild#get-guild-bans)
    def get_guild_bans(guild_id : UInt64 | Snowflake)
      response = request(
        :guilds_gid_bans,
        guild_id,
        "GET",
        "/guilds/#{guild_id}/bans",
        HTTP::Headers.new,
        nil
      )

      Array(GuildBan).from_json(response.body)
    end

    # Returns information about a banned user in a guild. Requires the "Ban Members"
    # permission.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/guild#get-guild-ban)
    def get_guild_ban(guild_id : UInt64 | Snowflake, user_id : UInt64 | Snowflake, reason : String? = nil)
      headers = HTTP::Headers.new
      headers["X-Audit-Log-Reason"] = reason if reason

      response = request(
        :guilds_gid_bans_uid,
        guild_id,
        "GET",
        "/guilds/#{guild_id}/bans/#{user_id}",
        headers,
        nil
      )

      GuildBan.from_json(response.body)
    end

    # Bans a member from the guild. Requires the "Ban Members" permission.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/guild#create-guild-ban)
    def create_guild_ban(guild_id : UInt64 | Snowflake, user_id : UInt64 | Snowflake,
                         delete_message_days : Int32? = nil, reason : String? = nil)
      json = encode_tuple(
        delete_message_days: delete_message_days,
        reason: reason,
      )

      request(
        :guilds_gid_bans_uid,
        guild_id,
        "PUT",
        "/guilds/#{guild_id}/bans/#{user_id}",
        HTTP::Headers{"Content-Type" => "application/json"},
        json,
      )
    end

    # Unbans a member from the guild. Requires the "Ban Members" permission.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/guild#remove-guild-ban)
    def remove_guild_ban(guild_id : UInt64 | Snowflake, user_id : UInt64 | Snowflake, reason : String? = nil)
      headers = HTTP::Headers.new
      headers["X-Audit-Log-Reason"] = reason if reason

      request(
        :guilds_gid_bans_uid,
        guild_id,
        "DELETE",
        "/guilds/#{guild_id}/bans/#{user_id}",
        headers,
        nil
      )
    end

    # Get a list of roles on the guild.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/guild#get-guild-roles)
    def get_guild_roles(guild_id : UInt64 | Snowflake)
      response = request(
        :guilds_gid_roles,
        guild_id,
        "GET",
        "/guilds/#{guild_id}/roles",
        HTTP::Headers.new,
        nil
      )

      Array(Role).from_json(response.body)
    end

    # Creates a new role on the guild. Requires the "Manage Roles" permission.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/guild#create-guild-role)
    def create_guild_role(guild_id : UInt64 | Snowflake, name : String? = nil,
                          permissions : Permissions? = nil, colour : UInt32 = 0_u32,
                          hoist : Bool = false, mentionable : Bool = false, reason : String? = nil)
      json = encode_tuple(
        name: name,
        permissions: permissions,
        color: colour,
        hoist: hoist,
        mentionable: mentionable
      )

      headers = HTTP::Headers{
        "Content-Type" => "application/json",
      }
      headers["X-Audit-Log-Reason"] = reason if reason

      response = request(
        :get_guild_roles,
        guild_id,
        "POST",
        "/guilds/#{guild_id}/roles",
        headers,
        json
      )

      Role.from_json(response.body)
    end

    # Changes a role's properties. Requires the "Manage Roles" permission as
    # well as the role to be lower than the bot's highest role.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/guild#modify-guild-role)
    def modify_guild_role(guild_id : UInt64 | Snowflake, role_id : UInt64 | Snowflake, name : String? = nil,
                          permissions : Permissions? = nil, colour : UInt32? = nil,
                          position : Int32? = nil, hoist : Bool? = nil, reason : String? = nil)
      json = encode_tuple(
        name: name,
        permissions: permissions,
        color: colour,
        position: position,
        hoist: hoist
      )

      headers = HTTP::Headers{
        "Content-Type" => "application/json",
      }
      headers["X-Audit-Log-Reason"] = reason if reason

      response = request(
        :guilds_gid_roles_rid,
        guild_id,
        "PATCH",
        "/guilds/#{guild_id}/roles/#{role_id}",
        headers,
        json
      )

      Role.from_json(response.body)
    end

    # Changes the position of roles. Requires the "Manage Roles" permission
    # and you cannot raise roles above the bot's highest role.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/guild#modify-guild-role-positions)
    def modify_guild_role_positions(guild_id : UInt64 | Snowflake,
                                    positions : Array(ModifyRolePositionPayload))
      response = request(
        :guilds_gid_roles,
        guild_id,
        "PATCH",
        "/guilds/#{guild_id}/roles",
        HTTP::Headers{"Content-Type" => "application/json"},
        positions.to_json
      )

      Array(Role).from_json(response.body)
    end

    # Deletes a role. Requires the "Manage Roles" permission as well as the role
    # to be lower than the bot's highest role.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/guild#delete-guild-role)
    def delete_guild_role(guild_id : UInt64 | Snowflake, role_id : UInt64 | Snowflake, reason : String? = nil)
      headers = HTTP::Headers.new
      headers["X-Audit-Log-Reason"] = reason if reason

      request(
        :guilds_gid_roles_rid,
        guild_id,
        "DELETE",
        "/guilds/#{guild_id}/roles/#{role_id}",
        headers,
        nil
      )
    end

    # Get a number of members that would be pruned with the given number of
    # days. Requires the "Kick Members" permission.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/guild#get-guild-prune-count)
    def get_guild_prune_count(guild_id : UInt64 | Snowflake, days : UInt32)
      response = request(
        :guilds_gid_prune,
        guild_id,
        "GET",
        "/guilds/#{guild_id}/prune?days=#{days}",
        HTTP::Headers.new,
        nil
      )

      PruneCountResponse.from_json(response.body)
    end

    # Prunes all members from this guild which haven't been seen for more than
    # *days* days. Requires the "Kick Members" permission.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/guild#begin-guild-prune)
    def begin_guild_prune(guild_id : UInt64 | Snowflake, days : UInt32, reason : String? = nil)
      headers = HTTP::Headers{
        "Content-Type" => "application/json",
      }
      headers["X-Audit-Log-Reason"] = reason if reason

      response = request(
        :guilds_gid_prune,
        guild_id,
        "POST",
        "/guilds/#{guild_id}/prune?days=#{days}",
        headers,
        nil
      )

      PruneCountResponse.from_json(response.body)
    end

    # Gets a list of voice regions available for this guild. This may include
    # VIP regions for VIP servers.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/guild#get-guild-voice-regions)
    def get_guild_voice_regions(guild_id : UInt64 | Snowflake)
      response = request(
        :guilds_gid_regions,
        guild_id,
        "GET",
        "/guilds/#{guild_id}/regions",
        HTTP::Headers.new,
        nil
      )

      Array(VoiceRegion).from_json(response.body)
    end

    # Gets a list of integrations (Twitch, YouTube, etc.) for this guild.
    # Requires the "Manage Guild" permission.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/guild#get-guild-integrations)
    def get_guild_integrations(guild_id : UInt64 | Snowflake)
      response = request(
        :guilds_gid_integrations,
        guild_id,
        "GET",
        "/guilds/#{guild_id}/integrations",
        HTTP::Headers.new,
        nil
      )

      Array(Integration).from_json(response.body)
    end

    # Creates a new integration for this guild. Requires the "Manage Guild"
    # permission.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/guild#create-guild-integration)
    def create_guild_integration(guild_id : UInt64 | Snowflake, type : String, id : UInt64 | Snowflake)
      json = encode_tuple(
        type: type,
        id: id
      )

      request(
        :guilds_gid_integrations,
        guild_id,
        "POST",
        "/guilds/#{guild_id}/integrations",
        HTTP::Headers{"Content-Type" => "application/json"},
        json
      )
    end

    # Modifies an existing guild integration. Requires the "Manage Guild"
    # permission.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/guild#modify-guild-integration)
    def modify_guild_integration(guild_id : UInt64 | Snowflake, integration_id : UInt64 | Snowflake,
                                 expire_behaviour : UInt8,
                                 expire_grace_period : Int32,
                                 enable_emoticons : Bool)
      json = encode_tuple(
        expire_behavior: expire_behaviour,
        expire_grace_period: expire_grace_period,
        enable_emoticons: enable_emoticons
      )

      request(
        :guilds_gid_integrations_iid,
        guild_id,
        "PATCH",
        "/guilds/#{guild_id}/integrations/#{integration_id}",
        HTTP::Headers{"Content-Type" => "application/json"},
        json
      )
    end

    # Deletes a guild integration. Requires the "Manage Guild" permission.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/guild#delete-guild-integration)
    def delete_guild_integration(guild_id : UInt64 | Snowflake, integration_id : UInt64 | Snowflake)
      request(
        :guilds_gid_integrations_iid,
        guild_id,
        "DELETE",
        "/guilds/#{guild_id}/integrations/#{integration_id}",
        HTTP::Headers.new,
        nil
      )
    end

    # Syncs an integration. Requires the "Manage Guild" permission.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/guild#sync-guild-integration)
    def sync_guild_integration(guild_id : UInt64 | Snowflake, integration_id : UInt64 | Snowflake)
      request(
        :guilds_gid_integrations_iid_sync,
        guild_id,
        "POST",
        "/guilds/#{guild_id}/integrations/#{integration_id}/sync",
        HTTP::Headers{"Content-Type" => "application/json"},
        nil
      )
    end

    # Gets embed data for a guild. Requires the "Manage Guild" permission.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/guild#get-guild-embed)
    def get_guild_embed(guild_id : UInt64 | Snowflake)
      response = request(
        :guilds_gid_embed,
        guild_id,
        "GET",
        "/guilds/#{guild_id}/embed",
        HTTP::Headers.new,
        nil
      )

      GuildEmbed.from_json(response.body)
    end

    # Modifies embed data for a guild. Requires the "Manage Guild" permission.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/guild#modify-guild-embed)
    def modify_guild_embed(guild_id : UInt64 | Snowflake, enabled : Bool,
                           channel_id : UInt64 | Snowflake)
      json = encode_tuple(
        enabled: enabled,
        channel_id: channel_id
      )

      response = request(
        :guilds_gid_embed,
        guild_id,
        "PATCH",
        "/guilds/#{guild_id}/embed",
        HTTP::Headers{"Content-Type" => "application/json"},
        json
      )

      GuildEmbed.from_json(response.body)
    end

    # Gets a specific user by ID.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/user#get-user)
    def get_user(user_id : UInt64 | Snowflake)
      response = request(
        :users_uid,
        nil,
        "GET",
        "/users/#{user_id}",
        HTTP::Headers.new,
        nil
      )

      User.from_json(response.body)
    end

    # Gets the current bot user.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/user#get-current-user)
    def get_current_user
      response = request(
        :users_me,
        nil,
        "GET",
        "/users/@me",
        HTTP::Headers.new,
        nil
      )

      User.from_json(response.body)
    end

    # Modifies the current bot user, changing the username and avatar.
    # NOTE: To remove the current user's avatar, you can send an empty string for the `avatar` argument.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/user#modify-current-user)
    def modify_current_user(username : String? = nil, avatar : String? = nil)
      json = encode_tuple(
        username: username,
        avatar: avatar
      )

      response = request(
        :users_me,
        nil,
        "PATCH",
        "/users/@me",
        HTTP::Headers{"Content-Type" => "application/json"},
        json
      )

      User.from_json(response.body)
    end

    # Gets a list of user guilds the current user is on.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/user#get-current-user-guilds)
    def get_current_user_guilds(limit : Int32 = 100, before : UInt64 | Snowflake = 0_u64, after : UInt64 | Snowflake = 0_u64)
      params = URI::Params.build do |form|
        form.add "limit", limit.to_s

        if before > 0_u64
          form.add "before", before.to_s
        end

        if after > 0_u64
          form.add "after", after.to_s
        end
      end

      path = "/users/@me/guilds?#{params}"
      response = request(
        :users_me_guilds,
        nil,
        "GET",
        path,
        HTTP::Headers.new,
        nil
      )

      Array(UserGuild).from_json(response.body)
    end

    # Returns a `Paginator` over the current users guilds.
    #
    # Will yield guilds in the given `direction` starting at `start_id` until
    # `limit` number of guilds are observed, or the user has no further guilds.
    # Setting `limit` to `nil` will have the paginator continue to make requests
    # until all guilds are fetched in the given `direction`.
    def page_current_user_guilds(start_id : UInt64 | Snowflake = 0_u64, limit : Int32? = 100,
                                 direction : Paginator::Direction = Paginator::Direction::Down,
                                 page_size : Int32 = 100)
      Paginator(UserGuild).new(limit, direction) do |last_page|
        if direction.up?
          next_id = last_page.try &.first.id || start_id
          get_current_user_guilds(page_size, before: next_id)
        else
          next_id = last_page.try &.last.id || start_id
          get_current_user_guilds(page_size, after: next_id)
        end
      end
    end

    # Makes the bot leave a guild.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/user#leave-guild)
    def leave_guild(guild_id : UInt64 | Snowflake)
      request(
        :users_me_guilds_gid,
        nil,
        "DELETE",
        "/users/@me/guilds/#{guild_id}",
        HTTP::Headers.new,
        nil
      )
    end

    # Gets a list of DM channels the bot has access to.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/user#get-user-dms)
    def get_user_dms
      response = request(
        :users_me_channels,
        nil,
        "GET",
        "/users/@me/channels",
        HTTP::Headers.new,
        nil
      )

      Array(PrivateChannel).from_json(response.body)
    end

    # Creates a new DM channel with a given recipient. If there was already one
    # before, it will be reopened.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/user#create-dm)
    def create_dm(recipient_id : UInt64 | Snowflake)
      response = request(
        :users_me_channels,
        nil,
        "POST",
        "/users/@me/channels",
        HTTP::Headers{"Content-Type" => "application/json"},
        {recipient_id: recipient_id}.to_json
      )

      PrivateChannel.from_json(response.body)
    end

    # Gets a list of connections the user has set up (Twitch, YouTube, etc.)
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/user#get-user-connections)
    def get_user_connections
      response = request(
        :users_me_connections,
        nil,
        "GET",
        "/users/@me/connections",
        HTTP::Headers.new,
        nil
      )

      Array(Connection).from_json(response.body)
    end

    # Gets a specific invite by its code.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/invite#get-invite)
    def get_invite(code : String)
      response = request(
        :invites_code,
        nil,
        "GET",
        "/invites/#{code}",
        HTTP::Headers.new,
        nil
      )

      Invite.from_json(response.body)
    end

    # Deletes (revokes) an invite. Requires the "Manage Channel" permission for
    # the channel the invite is for, or the "Manage Server" permission for the
    # server.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/invite#delete-invite)
    def delete_invite(code : String, reason : String? = nil)
      headers = HTTP::Headers.new
      headers["X-Audit-Log-Reason"] = reason if reason

      response = request(
        :invites_code,
        nil,
        "DELETE",
        "/invites/#{code}",
        headers,
        nil
      )

      Invite.from_json(response.body)
    end

    # Gets a list of voice regions newly created servers have access to.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/voice#list-voice-regions)
    def list_voice_regions
      response = request(
        :voice_regions,
        nil,
        "GET",
        "/voice/regions",
        HTTP::Headers.new,
        nil
      )

      Array(VoiceRegion).from_json(response.body)
    end

    # Get a webhook.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/webhook#get-webhook).
    def get_webhook(webhook_id : UInt64 | Snowflake)
      response = request(
        :webhooks_wid,
        webhook_id,
        "GET",
        "/webhooks/#{webhook_id}",
        HTTP::Headers.new,
        nil
      )
      Webhook.from_json(response.body)
    end

    # Get a webhook, with a token.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/webhook#get-webhook-with-token).
    def get_webhook(webhook_id : UInt64 | Snowflake, token : String)
      response = request(
        :webhooks_wid,
        webhook_id,
        "GET",
        "/webhooks/#{webhook_id}/#{token}",
        HTTP::Headers.new,
        nil
      )
      Webhook.from_json(response.body)
    end

    # Get an array of guild webhooks.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/webhook#get-guild-webhooks).
    def get_guild_webhooks(guild_id : UInt64 | Snowflake)
      response = request(
        :guilds_gid_webhooks,
        guild_id,
        "GET",
        "/guilds/#{guild_id}/webhooks",
        HTTP::Headers.new,
        nil
      )
      Array(Webhook).from_json(response.body)
    end

    # Create a channel webhook.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/webhook#create-webhook).
    def create_channel_webhook(channel_id : UInt64 | Snowflake, name : String,
                               avatar : String)
      json = {
        name:   name,
        avatar: avatar,
      }.to_json

      response = request(
        :channels_cid_webhooks,
        channel_id,
        "POST",
        "/channels/#{channel_id}/webhooks",
        HTTP::Headers{"Content-Type" => "application/json"},
        json
      )

      Webhook.from_json(response.body)
    end

    # Get an array of channel webhooks.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/webhook#get-channel-webhooks).
    def get_channel_webhooks(channel_id : UInt64 | Snowflake)
      response = request(
        :channels_cid_webhooks,
        channel_id,
        "GET",
        "/channels/#{channel_id}/webhooks",
        HTTP::Headers.new,
        nil
      )

      Array(Webhook).from_json(response.body)
    end

    # Modify a webhook. Accepts optional parameters `name`, `avatar`, and `channel_id`.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/webhook#modify-webhook).
    def modify_webhook(webhook_id : UInt64 | Snowflake, name : String? = nil, avatar : String? = nil,
                       channel_id : UInt64 | Snowflake | Nil = nil)
      json = encode_tuple(
        name: name,
        avatar: avatar,
        channel_id: channel_id
      )

      response = request(
        :webhooks_wid,
        webhook_id,
        "PATCH",
        "/webhooks/#{webhook_id}",
        HTTP::Headers{"Content-Type" => "application/json"},
        json
      )

      Webhook.from_json(response.body)
    end

    # Modify a webhook, with a token. Accepts optional parameters `name`, `avatar`, and `channel_id`.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/webhook#modify-webhook-with-token).
    def modify_webhook_with_token(webhook_id : UInt64 | Snowflake, token : String, name : String? = nil,
                                  avatar : String? = nil)
      json = encode_tuple(
        name: name,
        avatar: avatar
      )

      response = request(
        :webhooks_wid,
        webhook_id,
        "PATCH",
        "/webhooks/#{webhook_id}/#{token}",
        HTTP::Headers{"Content-Type" => "application/json"},
        json
      )

      Webhook.from_json(response.body)
    end

    # Deletes a webhook. User must be owner.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/webhook#delete-webhook)
    def delete_webhook(webhook_id : UInt64 | Snowflake)
      request(
        :webhooks_wid,
        webhook_id,
        "DELETE",
        "/webhooks/#{webhook_id}",
        HTTP::Headers.new,
        nil
      )
    end

    # Deletes a webhook with a token. Does not require authentication.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/webhook#delete-webhook-with-token)
    def delete_webhook(webhook_id : UInt64 | Snowflake, token : String)
      request(
        :webhooks_wid,
        webhook_id,
        "DELETE",
        "/webhooks/#{webhook_id}/#{token}",
        HTTP::Headers.new,
        nil
      )
    end

    # Executes a webhook, with a token.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/webhook#execute-webhook)
    def execute_webhook(webhook_id : UInt64 | Snowflake, token : String, content : String? = nil,
                        file : String? = nil, embeds : Array(Embed)? = nil,
                        tts : Bool? = nil, avatar_url : String? = nil,
                        username : String? = nil, allowed_mentions : AllowedMentions? = nil,
                        wait : Bool? = false, thread_id : UInt64 | Snowflake? = nil)
      json = encode_tuple(
        content: content,
        file: file,
        embeds: embeds,
        tts: tts,
        avatar_url: avatar_url,
        username: username,
        allowed_mentions: allowed_mentions
      )

      params = URI::Params.build do |form|
        form.add "wait", wait if wait
        form.add "thread_id", thread_id if thread_id
      end

      response = request(
        :webhooks_wid,
        webhook_id,
        "POST",
        "/webhooks/#{webhook_id}/#{token}?#{params}",
        HTTP::Headers{"Content-Type" => "application/json"},
        json
      )

      # Expecting response
      Message.from_json(response.body) if wait
    end
  end
end
