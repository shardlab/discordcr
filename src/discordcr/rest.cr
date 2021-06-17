module Discord
  module REST
    SSL_CONTEXT = OpenSSL::SSL::Context::Client.new
    USER_AGENT  = "DiscordBot (https://github.com/shardlab/discordcr, #{Discord::VERSION})"
    API_BASE    = "https://discord.com/api/v#{API_VERSION}"

    Log = Discord::Log.for("rest")

    alias RateLimitKey = {route_key: Symbol, major_parameter: UInt64?}

    # Like `#request`, but does not do error checking beyond 429.
    def raw_request(route_key : Symbol, major_parameter : Snowflake | UInt64 | Nil, method : String, path : String, headers : HTTP::Headers, body : String | IO::Memory | Nil)
      mutexes = (@mutexes ||= Hash(RateLimitKey, Mutex).new)
      global_mutex = (@global_mutex ||= Mutex.new)

      headers["Authorization"] = @token
      headers["User-Agent"] = USER_AGENT

      request_done = false
      rate_limit_key = {route_key: route_key, major_parameter: major_parameter.try(&.to_u64)}

      until request_done
        mutexes[rate_limit_key] ||= Mutex.new

        # Make sure to catch up with existing mutexes - they may be locked from
        # another fiber.
        mutexes[rate_limit_key].synchronize { }
        global_mutex.synchronize { }

        Log.info { "[HTTP OUT] #{method} #{path} (#{body.try &.size || 0} bytes)" }
        Log.debug { "[HTTP OUT] BODY: #{body}" } if body.is_a?(String)

        body.rewind if body.is_a?(IO::Memory)

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
    def request(route_key : Symbol, major_parameter : Snowflake | UInt64 | Nil, method : String, path : String, headers : HTTP::Headers, body : String | IO::Memory | Nil)
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
            builder.field(key) { (value.is_a?(Enum) ? value.value : value).to_json(builder) }
          end
        end
      end
    end

    # :nodoc:
    def header_with_reason(content_type : String?, reason : String?) : HTTP::Headers
      header = HTTP::Headers.new
      header["Content-Type"] = content_type if content_type
      header["X-Audit-Log-Reason"] = reason if reason
      header
    end

    #
    # Topics -> Gateway
    #

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

    #
    # Topics -> OAuth2
    #

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

      Application.from_json(response.body)
    end

    #
    # Resources -> Audit Log
    #

    # Returns an audit log object for the guild.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/audit-log#get-guild-audit-log)
    def get_audit_log(guild_id : UInt64 | Snowflake, user_id : UInt64 | Snowflake | Nil = nil, action_type : UInt32 | AuditLogEvent | Nil = nil, before : UInt64 | Snowflake | Nil = nil, limit : UInt32? = nil)
      query = user_id.nil? ? "" : "user_id=#{user_id}"
      query += "&action_type=#{action_type}" if action_type
      query += "&before=#{before}" if before
      query += "&limit=#{limit}" if limit
      query = "?#{query[0] == '&' ? query[1..] : query}" if query != ""
      response = request(
        :audit_log_gid,
        guild_id,
        "GET",
        "/guilds/#{guild_id}/audit-logs#{query}",
        HTTP::Headers.new,
        nil
      )

      AuditLog.from_json(response.body)
    end

    #
    # Resources -> Channel
    #

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

    # Modifies a DM channel with new properties.
    # icon argument should contain a base64 encoded icon.
    # icon_file argument should contain a path to an icon file.
    # icon argument takes priority over icon_file.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/channel#modify-channel)
    def modify_dm_channel(channel_id : UInt64 | Snowflake, name : String? = nil, icon : String? = nil, icon_file : String? = nil)
      icon = Base64.encode(File.read(icon_file)).gsub("\n", "") if icon.nil? && !icon_file.nil?

      json = encode_tuple(
        name: name,
        icon: icon,
      )

      response = request(
        :channels_cid,
        channel_id,
        "PATCH",
        "/channels/#{channel_id}",
        HTTP::Headers{"Content-Type" => "application/json"},
        json
      )

      PrivateChannel.from_json(response.body)
    end

    # Modifies a channel with new properties. Requires the "Manage Channel"
    # permission.
    #
    # NOTE: To see valid fields, see `VALID_MODIFY_CHANNEL_ARGS` constant (beneath this method in code)
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/channel#modify-channel)
    def modify_channel(channel_id : UInt64 | Snowflake, reason : String? = nil, **args : **T) forall T
      json = TypeCheck.args_check(args, VALID_MODIFY_CHANNEL_ARGS)

      response = request(
        :channels_cid,
        channel_id,
        "PATCH",
        "/channels/#{channel_id}",
        header_with_reason("application/json", reason),
        json.to_json
      )

      Channel.from_json(response.body)
    end

    VALID_MODIFY_CHANNEL_ARGS = {
      :name                  => TypeCheck(String),
      :type                  => TypeCheck(UInt8 | ChannelType),
      :position              => TypeCheck(UInt32?),
      :topic                 => TypeCheck(String?),
      :nsfw                  => TypeCheck(Bool?),
      :rate_limit_per_user   => TypeCheck(UInt32?),
      :bitrate               => TypeCheck(UInt32?),
      :user_limit            => TypeCheck(UInt32?),
      :permission_overwrites => TypeCheck(Array(Overwrite)?),
      :parent_id             => TypeCheck(UInt64 | Snowflake | Nil),
      :rtc_region            => TypeCheck(String?),
      :video_quality_mode    => TypeCheck(UInt8 | VideoQualityMode | Nil),
    }

    # Deletes a channel by ID. Requires the "Manage Channel" permission.
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
      query = "limit=#{limit}"
      query += "&before=#{before}" if before
      query += "&after=#{after}" if after
      query += "&around=#{around}" if around

      response = request(
        :channels_cid_messages,
        channel_id,
        "GET",
        "/channels/#{channel_id}/messages?#{query}",
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
    # client.create_message(channel_id, "The content of the message. This will display separately above the embed. This string can be empty.", [embed])
    # ```
    #
    # For more details on the format of the `embed` object, look at the
    # [relevant documentation](https://discord.com/developers/docs/resources/channel#embed-object).
    def create_message(channel_id : UInt64 | Snowflake, content : String? = nil, embeds : Array(Embed)? = nil, file : String | IO | Nil = nil,
                       filename : String? = nil, tts : Bool = false, allowed_mentions : AllowedMentions? = nil,
                       message_reference : MessageReference? = nil, components : Array(Component)? = nil,
                       nonce : Int64 | String? = nil)
      body = encode_tuple(
        content: content,
        tts: tts,
        embeds: embeds,
        allowed_mentions: allowed_mentions,
        message_reference: message_reference,
        components: components,
        nonce: nonce,
      )

      content_type = "application/json"
      body, content_type = send_file(body, file, filename) if file

      response = request(
        :channels_cid_messages,
        channel_id,
        "POST",
        "/channels/#{channel_id}/messages",
        HTTP::Headers{"Content-Type" => content_type},
        body
      )

      Message.from_json(response.body)
    end

    # :nodoc:
    private def send_file(old_body : String, file : String | IO | Nil, filename : String?) : {IO::Memory, String}
      file = File.open(file) if file.is_a?(String)
      filename = (file.is_a?(File) ? File.basename(file.path) : "") unless filename
      builder = HTTP::FormData::Builder.new((io = IO::Memory.new))
      builder.field("payload_json", old_body, HTTP::Headers{"Content-Type" => "application/json"})
      builder.file("file", file, HTTP::FormData::FileMetadata.new(filename: filename))
      builder.finish
      {io, builder.content_type}
    end

    # Uploads a file to a channel. Requires the "Send Messages" and "Attach
    # Files" permissions.
    #
    # If the specified `file` is a `File` object and no filename is specified,
    # the file's filename will be used instead. If it is an `IO` without
    # filename information, Discord will generate a placeholder filename.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/channel#create-message)
    # (same as `#create_message` -- this method only )
    def upload_file(channel_id : UInt64 | Snowflake, content : String?, file : IO, filename : String? = nil, spoiler : Bool = false)
      filename = (file.is_a?(File) ? File.basename(file.path) : "") unless filename
      filename = "SPOILER_" + filename if spoiler && !filename.starts_with?("SPOILER_")

      create_message(channel_id, content, file: file, filename: filename)
    end

    # Crosspost a message in a News Channel to following channels.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/channel#create-message)
    def corsspost_message(channel_id : UInt64 | Snowflake, message_id : UInt64 | Snowflake)
      response = request(
        :channels_cid_messages_mid_crosspost,
        channel_id,
        "POST",
        "/channels/#{channel_id}/messages/#{message_id}/crosspost",
        HTTP::Headers.new,
        nil
      )

      Message.from_json(response.body)
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
    def get_reactions(channel_id : UInt64 | Snowflake, message_id : UInt64 | Snowflake, emoji : String, limit : UInt32 = 25, after : UInt64 | Snowflake | Nil = nil)
      query = "limit=#{limit}"
      query += "&after=#{after}" if after
      response = request(
        :channels_cid_messages_mid_reactions_emoji_me,
        channel_id,
        "GET",
        "/channels/#{channel_id}/messages/#{message_id}/reactions/#{URI.encode(emoji)}?#{query}",
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

    # Edits an existing message on the channel. This only works for messages
    # sent by the bot itself - you can't edit others' messages.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/channel#edit-message)
    def edit_message(channel_id : UInt64 | Snowflake, message_id : UInt64 | Snowflake, content : String? = nil, embeds : Array(Embed)? = nil,
                     file : String | IO | Nil = nil, filename : String? = nil, flags : UInt8 | MessageFlags | Nil = nil,
                     allowed_mentions : AllowedMentions? = nil, components : Array(Component)? = nil)
      body = encode_tuple(
        content: content,
        embeds: embeds,
        flags: flags,
        allowed_mentions: allowed_mentions,
        components: components,
      )

      content_type = "application/json"
      body, content_type = send_file(body, file, filename) if file

      response = request(
        :channels_cid_messages_mid,
        channel_id,
        "PATCH",
        "/channels/#{channel_id}/messages/#{message_id}",
        HTTP::Headers{"Content-Type" => content_type},
        body
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
                                 type : OverwriteType, allow : Permissions? = nil, deny : Permissions? = nil, reason : String? = nil)
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
        header_with_reason("application/json", reason),
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
    def create_channel_invite(channel_id : UInt64 | Snowflake, max_age : UInt32 = 86400_u32,
                              max_uses : UInt32 = 0_u32, temporary : Bool = false, unique : Bool = false,
                              target_type : UInt8 | InviteTargetType | Nil = nil, target_user_id : UInt64 | Snowflake | Nil = nil,
                              target_application_id : UInt64 | Snowflake | Nil = nil, reason : String? = nil)
      json = encode_tuple(
        max_age: max_age,
        max_uses: max_uses,
        temporary: temporary,
        unique: unique,
        target_type: target_type,
        target_user_id: target_user_id,
        target_application_id: target_application_id,
      )

      response = request(
        :channels_cid_invites,
        channel_id,
        "POST",
        "/channels/#{channel_id}/invites",
        header_with_reason("application/json", reason),
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

    # Follow a News Channel to send messages to a target webhook channel.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/channel#follow-news-channel)
    def follow_news_channel(channel_id : UIn64 | Snowflake, webhook_channel_id : UInt64 | Snowflake)
      response = request(
        :channels_cid_followers,
        channel_id,
        "POST",
        "/channels/#{channel_id}/followers",
        HTTP::Headers{"Content-Type" => "application/json"},
        {webhook_channel_id: webhook_channel_id}.to_json
      )

      FollowedChannel.from_json(response.body)
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
    # [API docs for this method](https://discord.com/developers/docs/resources/channel#pin-message)
    def add_pinned_channel_message(channel_id : UInt64 | Snowflake, message_id : UInt64 | Snowflake, reason : String? = nil)
      pin_message(channel_id, message_id, reason)
    end

    # Pins a new message to this channel. Requires the "Manage Messages"
    # permission.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/channel#pin-message)
    def pin_message(channel_id : UInt64 | Snowflake, message_id : UInt64 | Snowflake, reason : String? = nil)
      response = request(
        :channels_cid_pins_mid,
        channel_id,
        "PUT",
        "/channels/#{channel_id}/pins/#{message_id}",
        header_with_reason(nil, reason),
        nil
      )
    end

    # Unpins a message from this channel. Requires the "Manage Messages"
    # permission.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/channel#unpin-message)
    def delete_pinned_channel_message(channel_id : UInt64 | Snowflake, message_id : UInt64 | Snowflake)
      unpin_message(channel_id, message_id)
    end

    # Unpins a message from this channel. Requires the "Manage Messages"
    # permission.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/channel#unpin-message)
    def unpin_message(channel_id : UInt64 | Snowflake, message_id : UInt64 | Snowflake)
      response = request(
        :channels_cid_pins_mid,
        channel_id,
        "DELETE",
        "/channels/#{channel_id}/pins/#{message_id}",
        HTTP::Headers.new,
        nil
      )
    end

    # Adds a recipient to a Group DM using their access token.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/channel#group-dm-add-recipient)
    def group_dm_add_recipiant(channel_id : UInt64 | Snowflake, user_id : UInt64 | Snowflake, access_token : String? = nil, nick : String? = nil)
      response = request(
        :channels_cid_recipients_uid,
        channel_id,
        "PUT",
        "/channels/#{channel_id}/recipients/#{user_id}",
        HTTP::Headers{"Content-Type" => "application/json"},
        {access_token: access_token, nick: nick}.to_json
      )
    end

    # Removes a recipient from a Group DM.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/channel#group-dm-remove-recipient)
    def group_dm_remove_recipiant(channel_id : UInt64 | Snowflake, user_id : UInt64 | Snowflake)
      response = request(
        :channels_cid_recipients_uid,
        channel_id,
        "DELETE",
        "/channels/#{channel_id}/recipients/#{user_id}",
        HTTP::Headers.new,
        nil
      )
    end

    #
    # Resources -> Emoji
    #

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

    # Creates a guild emoji. Requires the "Manage Emojis" permission.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/emoji#create-guild-emoji)
    def create_guild_emoji(guild_id : UInt64 | Snowflake, name : String, image : String, roles : Array(UInt64 | Snowflake)? = nil, reason : String? = nil)
      json = encode_tuple(
        name: name,
        image: image,
        roles: roles,
      )

      response = request(
        :guilds_gid_emojis,
        guild_id,
        "POST",
        "/guilds/#{guild_id}/emojis",
        header_with_reason("application/json", reason),
        json
      )

      Emoji.from_json(response.body)
    end

    # Modifies a guild emoji. Requires the "Manage Emojis" permission.
    #
    # NOTE: To see valid fields, see `VALID_MODIFY_GUILD_EMOJI_ARGS` constant (beneath this method in code)
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/emoji#modify-guild-emoji)
    def modify_guild_emoji(guild_id : UInt64 | Snowflake, emoji_id : UInt64 | Snowflake, reason : String? = nil, **args : **T) forall T
      json = TypeCheck.args_check(args, VALID_MODIFY_GUILD_EMOJI_ARGS)

      response = request(
        :guilds_gid_emojis_eid,
        guild_id,
        "PATCH",
        "/guilds/#{guild_id}/emojis/#{emoji_id}",
        header_with_reason("application/json", reason),
        json.to_json
      )

      Emoji.from_json(response.body)
    end

    VALID_MODIFY_GUILD_EMOJI_ARGS = {
      :name  => TypeCheck(String),
      :roles => TypeCheck(Array(UInt64 | Snowflake)?),
    }

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

    #
    # Resources -> Guild
    #

    # Gets a guild by ID.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/guild#get-guild)
    def get_guild(guild_id : UInt64 | Snowflake, with_counts : Bool = false)
      response = request(
        :guilds_gid,
        guild_id,
        "GET",
        "/guilds/#{guild_id}?with_counts=#{with_counts}",
        HTTP::Headers.new,
        nil
      )

      Guild.from_json(response.body)
    end

    # Gets a guild preview by ID.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/guild#get-guild-preview)
    def get_guild_preview(guild_id : UInt64 | Snowflake)
      response = request(
        :guilds_gid_preview,
        guild_id,
        "GET",
        "/guilds/#{guild_id}/preview",
        HTTP::Headers.new,
        nil
      )

      GuildPreview.from_json(response.body)
    end

    # Modifies an existing guild with new properties. Requires the "Manage
    # Server" permission.
    # NOTE: To remove a guild's icon, you can send an empty string or nil for the `icon` argument.
    # NOTE: To see valid fields, see `VALID_MODIFY_GUILD_ARGS` constant (beneath this method in code)
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/guild#modify-guild)
    def modify_guild(guild_id : UInt64 | Snowflake, reason : String? = nil, **args : **T) forall T
      json = TypeCheck.args_check(args, VALID_MODIFY_GUILD_ARGS)

      response = request(
        :guilds_gid,
        guild_id,
        "PATCH",
        "/guilds/#{guild_id}",
        header_with_reason("application/json", reason),
        json.to_json
      )

      Guild.from_json(response.body)
    end

    # This Hash contains the valid arguments for `#modify_guild` method.
    # Each pair describes a valid field present in [Discord's documentation](https://discord.com/developers/docs/resources/guild#modify-guild-json-params)
    VALID_MODIFY_GUILD_ARGS = {
      :name                          => TypeCheck(String),
      :region                        => TypeCheck(String?),
      :verification_level            => TypeCheck(UInt8 | VerificationLevel | Nil),
      :default_message_notifications => TypeCheck(UInt8 | MessageNotificationLevel | Nil),
      :explicit_content_filter       => TypeCheck(UInt8 | ExplicitContentFilter | Nil),
      :afk_channel_id                => TypeCheck(UInt64 | Snowflake | Nil),
      :afk_timeout                   => TypeCheck(Int32),
      :icon                          => TypeCheck(String?),
      :owner_id                      => TypeCheck(UInt64 | Snowflake),
      :splash                        => TypeCheck(String?),
      :discovery_splash              => TypeCheck(String?),
      :banner                        => TypeCheck(String?),
      :system_channel_id             => TypeCheck(UInt64 | Snowflake | Nil),
      :system_channel_flags          => TypeCheck(UInt8 | SystemChannelFlags),
      :rules_channel_id              => TypeCheck(UInt64 | Snowflake | Nil),
      :public_updates_channel_id     => TypeCheck(UInt64 | Snowflake | Nil),
      :preferred_locale              => TypeCheck(String?),
      :features                      => TypeCheck(Array(String)),
      :description                   => TypeCheck(String?),
    }

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
    def create_guild_channel(guild_id : UInt64 | Snowflake, name : String, type : UInt8 | ChannelType | Nil = nil, topic : String? = nil,
                             bitrate : UInt32? = nil, user_limit : UInt32? = nil, rate_limit_per_user : Int32? = nil,
                             position : UInt32? = nil, permission_overwrites : Array(Overwrite)? = nil,
                             parent_id : UInt64 | Snowflake | Nil = nil, nsfw : Bool? = nil, reason : String? = nil)
      json = encode_tuple(
        name: name,
        type: type,
        topic: topic,
        bitrate: bitrate,
        user_limit: user_limit,
        rate_limit_per_user: rate_limit_per_user,
        position: position,
        permission_overwrites: permission_overwrites,
        parent_id: parent_id,
        nsfw: nsfw
      )

      response = request(
        :guilds_gid_channels,
        guild_id,
        "POST",
        "/guilds/#{guild_id}/channels",
        header_with_reason("application/json", reason),
        json
      )

      Channel.from_json(response.body)
    end

    # Modifies the position of channels within a guild. Requires the
    # "Manage Channels" permission.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/guild#modify-guild-channel-positions)
    def modify_guild_channel_positions(guild_id : UInt64 | Snowflake, positions : Array(ModifyChannelPositionPayload), reason : String? = nil)
      request(
        :guilds_gid_channels,
        guild_id,
        "PATCH",
        "/guilds/#{guild_id}/channels",
        header_with_reason("application/json", reason),
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
    def list_guild_members(guild_id : UInt64 | Snowflake, limit : Int32 = 1000, after : UInt64 | Snowflake | Nil = nil)
      query = "limit=#{limit}"
      query += "&after=#{after}" if after

      response = request(
        :guilds_gid_members,
        guild_id,
        "GET",
        "/guilds/#{guild_id}/members?#{query}",
        HTTP::Headers.new,
        nil
      )

      Array(GuildMember).from_json(response.body)
    end

    # Returns a `Paginator` over the given guilds members.
    #
    # Will yield members starting at `start_id` until `limit` number of members
    # guilds are observed, or the user has no further guilds. Setting `limit`
    # to `nil` will have the paginator continue to make requests until all members
    # are fetched.
    def page_guild_members(guild_id : UInt64 | Snowflake, start_id : UInt64 | Snowflake = 0_u64, limit : Int32? = 1000, page_size : Int32 = 1000)
      Paginator(GuildMember).new(limit, Paginator::Direction::Down) do |last_page|
        next_id = last_page.try &.last.user.id || start_id
        list_guild_members(guild_id, page_size, next_id)
      end
    end

    # Returns a list of guild member objects whose username or nickname starts with a provided string.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/guild#search-guild-members)
    def search_guild_members(guild_id : UInt64 | Snowflake, query : String, limit : Int32 = 1)
      response = request(
        :guilds_gid_members_search,
        guild_id,
        "GET",
        "/guilds/#{guild_id}/members/search?query=#{URI.encode(query)}&limit=#{limit}",
        HTTP::Headers.new,
        nil
      )

      Array(GuildMember).from_json(response.body)
    end

    # Adds a user to the guild, provided you have a valid OAuth2 access token
    # for the user with the `guilds.join` scope.
    #
    # NOTE: The bot must be a member of the target guild, and have permissions
    #   to create instant invites.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/guild#add-guild-member)
    def add_guild_member(guild_id : UInt64, user_id : UInt64, access_token : String, nick : String? = nil,
                         roles : Array(UInt64 | Snowflake)? = nil, mute : Bool? = nil, deaf : Bool? = nil)
      json = encode_tuple(
        access_token: access_token,
        nick: nick,
        roles: roles,
        mute: mute,
        deaf: deaf,
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
    # NOTE: To remove a member's nickname, you can send an empty string or nil for the `nick` argument.
    # NOTE: To see valid fields, see `VALID_MODIFY_GUILD_MEMBER_ARGS` constant (beneath this method in code)
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/guild#modify-guild-member)
    def modify_guild_member(guild_id : UInt64 | Snowflake, user_id : UInt64 | Snowflake, reason : String? = nil, **args : **T) forall T
      json = TypeCheck.args_check(args, VALID_MODIFY_GUILD_MEMBER_ARGS)

      response = request(
        :guilds_gid_members_uid,
        guild_id,
        "PATCH",
        "/guilds/#{guild_id}/members/#{user_id}",
        header_with_reason("application/json", reason),
        json.to_json
      )

      GuildMember.from_json(response.body)
    end

    # This Hash contains the valid arguments for `#modify_guild_member` method.
    # Each pair describes a valid field present in [Discord's documentation](https://discord.com/developers/docs/resources/guild#modify-guild-member-json-params)
    VALID_MODIFY_GUILD_MEMBER_ARGS = {
      :nick       => TypeCheck(String?),
      :roles      => TypeCheck(Array(UInt64 | Snowflake)?),
      :mute       => TypeCheck(Bool?),
      :deaf       => TypeCheck(Bool?),
      :channel_id => TypeCheck(UInt64 | Snowflake | Nil),
    }

    # Modifies the nickname of the current user in a guild.
    #
    # NOTE: To remove a nickname, you can send an empty string or nil for the `nick` argument.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/guild#modify-current-user-nick)
    def modify_current_user_nick(guild_id : UInt64 | Snowflake, nick : String?, reason : String? = nil)
      request(
        :guilds_gid_members_me,
        guild_id,
        "PATCH",
        "/guilds/#{guild_id}/members/@me/nick",
        header_with_reason("application/json", reason), # HTTP::Headers{"Content-Type" => "application/json"},
        {nick: nick}.to_json
      )
    end

    # Adds a role to a member. Requires the "Manage Roles" permission.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/guild#add-guild-member-role)
    def add_guild_member_role(guild_id : UInt64 | Snowflake, user_id : UInt64 | Snowflake, role_id : UInt64 | Snowflake, reason : String? = nil)
      request(
        :guilds_gid_members_uid_roles_rid,
        guild_id,
        "PUT",
        "/guilds/#{guild_id}/members/#{user_id}/roles/#{role_id}",
        header_with_reason(nil, reason),
        nil
      )
    end

    # Removes a role from a member. Requires the "Manage Roles" permission.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/guild#remove-guild-member-role)
    def remove_guild_member_role(guild_id : UInt64 | Snowflake, user_id : UInt64 | Snowflake, role_id : UInt64 | Snowflake)
      request(
        :guilds_gid_members_uid_roles_rid,
        guild_id,
        "DELETE",
        "/guilds/#{guild_id}/members/#{user_id}/roles/#{role_id}",
        HTTP::Headers.new,
        nil
      )
    end

    # Kicks a member from the server. Requires the "Kick Members" permission.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/guild#remove-guild-member)
    def remove_guild_member(guild_id : UInt64 | Snowflake, user_id : UInt64 | Snowflake, reason : String? = nil)
      request(
        :guilds_gid_members_uid,
        guild_id,
        "DELETE",
        "/guilds/#{guild_id}/members/#{user_id}",
        header_with_reason(nil, reason),
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
    def get_guild_ban(guild_id : UInt64 | Snowflake, user_id : UInt64 | Snowflake)
      response = request(
        :guilds_gid_bans_uid,
        guild_id,
        "GET",
        "/guilds/#{guild_id}/bans/#{user_id}",
        HTTP::Headers.new,
        nil
      )

      GuildBan.from_json(response.body)
    end

    # Bans a member from the guild. Requires the "Ban Members" permission.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/guild#create-guild-ban)
    def create_guild_ban(guild_id : UInt64 | Snowflake, user_id : UInt64 | Snowflake, delete_message_days : UInt32? = nil, reason : String? = nil)
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
      request(
        :guilds_gid_bans_uid,
        guild_id,
        "DELETE",
        "/guilds/#{guild_id}/bans/#{user_id}",
        header_with_reason(nil, reason),
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
                          permissions : Permissions? = nil, colour : UInt32? = nil,
                          hoist : Bool = false, mentionable : Bool = false, reason : String? = nil)
      json = encode_tuple(
        name: name,
        permissions: permissions,
        color: colour,
        hoist: hoist,
        mentionable: mentionable,
      )

      response = request(
        :get_guild_roles,
        guild_id,
        "POST",
        "/guilds/#{guild_id}/roles",
        header_with_reason("application/json", reason),
        json
      )

      Role.from_json(response.body)
    end

    # Changes the position of roles. Requires the "Manage Roles" permission
    # and you cannot raise roles above the bot's highest role.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/guild#modify-guild-role-positions)
    def modify_guild_role_positions(guild_id : UInt64 | Snowflake, positions : Array(ModifyRolePositionPayload))
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

    # Changes a role's properties. Requires the "Manage Roles" permission as
    # well as the role to be lower than the bot's highest role.
    #
    # NOTE: To see valid fields, see `VALID_MODIFY_GUILD_ROLE_ARGS` constant (beneath this method in code)
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/guild#modify-guild-role)
    def modify_guild_role(guild_id : UInt64 | Snowflake, role_id : UInt64 | Snowflake, reason : String? = nil, **args : **T) forall T
      json = TypeCheck.args_check(args, VALID_MODIFY_GUILD_ROLE_ARGS)
      json["color"] = json.delete("colour").not_nil! if json.has_key? "colour"

      response = request(
        :guilds_gid_roles_rid,
        guild_id,
        "PATCH",
        "/guilds/#{guild_id}/roles/#{role_id}",
        header_with_reason("application/json", reason),
        json.to_json
      )

      Role.from_json(response.body)
    end

    VALID_MODIFY_GUILD_ROLE_ARGS = {
      :name        => TypeCheck(String?),
      :permissions => TypeCheck(Permissions?),
      :colour      => TypeCheck(UInt32?),
      :hoist       => TypeCheck(Bool?),
      :mentionable => TypeCheck(Bool?),
    }

    # Deletes a role. Requires the "Manage Roles" permission as well as the role
    # to be lower than the bot's highest role.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/guild#delete-guild-role)
    def delete_guild_role(guild_id : UInt64 | Snowflake, role_id : UInt64 | Snowflake)
      request(
        :guilds_gid_roles_rid,
        guild_id,
        "DELETE",
        "/guilds/#{guild_id}/roles/#{role_id}",
        HTTP::Headers.new,
        nil
      )
    end

    # Get a number of members that would be pruned with the given number of
    # days. Requires the "Kick Members" permission.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/guild#get-guild-prune-count)
    def get_guild_prune_count(guild_id : UInt64 | Snowflake, days : UInt32 = 7, include_roles : Array(UInt64 | Snowflake)? = nil)
      query = "days=#{days}"
      query += "include_roles=#{include_roles.map(&.to_s).join(",")}" if include_roles

      response = request(
        :guilds_gid_prune,
        guild_id,
        "GET",
        "/guilds/#{guild_id}/prune?#{query}",
        HTTP::Headers.new,
        nil
      )

      PruneCountResponse.from_json(response.body)
    end

    # Prunes all members from this guild which haven't been seen for more than
    # *days* days. Requires the "Kick Members" permission.
    # For large guilds it's recommended to set the compute_prune_count option to false, forcing 'pruned' to null.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/guild#begin-guild-prune)
    def begin_guild_prune(guild_id : UInt64 | Snowflake, days : UInt32 = 7, compute_prune_count : Bool? = nil, include_roles : Array(UInt64 | Snowflake)? = nil, reason : String? = nil)
      json = encode_tuple(
        days: days,
        compute_prune_count: compute_prune_count,
        include_roles: include_roles,
        reson: reason,
      )

      response = request(
        :guilds_gid_prune,
        guild_id,
        "POST",
        "/guilds/#{guild_id}/prune?days=#{days}",
        HTTP::Headers{"Content-Type" => "application/json"},
        json
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

    # Returns a list of invite objects (with invite metadata) for the guild.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/guild#get-guild-invites)
    def get_guild_invites(guild_id : UInt64 | Snowflake)
      response = request(
        :guilds_gid_invites,
        guild_id,
        "GET",
        "/guilds/#{guild_id}/invites",
        HTTP::Headers.new,
        nil
      )

      Array(InviteMetadata).from_json(response.body)
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
    # DEPRECATED: This method is not logner present in Discord documentation
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
    # DEPRECATED: This method is not logner present in Discord documentation
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
    # DEPRECATED: This method is not logner present in Discord documentation
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

    # Returns a guild widget object. Requires the "Manage Guild" permission.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/guild#get-guild-widget-settings)
    def get_guild_widget_settings(guild_id : UInt64 | Snowflake)
      response = request(
        :guilds_gid_widget,
        guild_id,
        "GET",
        "/guilds/#{guild_id}/widget",
        HTTP::Headers.new,
        nil
      )

      GuildWidgetSettings.from_json(response.body)
    end

    # Modify a guild widget object for the guild. Requires the "Manage Guild" permission.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/guild#modify-guild-widget)
    def modify_guild_widget(guild_id : UInt64 | Snowflake, enabled : Bool? = nil, channel_id : UInt64 | Snowflake | Nil = nil)
      json = encode_tuple(
        enabled: enabled,
        channel_id: channel_id
      )

      response = request(
        :guilds_gid_widget,
        guild_id,
        "PATCH",
        "/guilds/#{guild_id}/widget",
        HTTP::Headers{"Content-Type" => "application/json"},
        json
      )

      GuildWidgetSettings.from_json(response.body)
    end

    # Returns the widget for the guild.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/guild#get-guild-widget)
    def get_guild_widget(guild_id : UInt64 | Snowflake)
      response = request(
        :guilds_gid_widgetjson,
        guild_id,
        "GET",
        "/guilds/#{guild_id}/widget.json",
        HTTP::Headers.new,
        nil
      )

      GuildWidget.from_json(response.body)
    end

    # Gets the vanity URL of a guild. Requires the guild to be partnered.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/guild#get-guild-vanity-url)
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

    # Returns the Welcome Screen object for the guild.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/guild#get-guild-welcome-screen)
    def get_guild_welcome_screen(guild_id : UInt64 | Snowflake)
      response = request(
        :guilds_gid_welcome_screen,
        guild_id,
        "GET",
        "/guilds/#{guild_id}/welcome-screen",
        HTTP::Headers.new,
        nil
      )

      WelcomeScreen.from_json(response.body)
    end

    # Modify the guild's Welcome Screen. Requires the "Manage Guild" permission.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/guild#modify-guild-welcome-screen)
    def modify_guild_welcome_screen(guild_id : UInt64 | Snowflake, enabled : Bool? = nil, welcome_channels : Array(WelcomeChannel)? = nil, description : String? = nil)
      json = encode_tuple(
        enabled: enabled,
        welcome_channels: welcome_channels,
        description: description,
      )

      response = request(
        :guilds_gid_welcome_screen,
        guild_id,
        "PATCH",
        "/guilds/#{guild_id}/welcome-screen",
        HTTP::Headers.new,
        nil
      )

      WelcomeScreen.from_json(response.body)
    end

    #
    # Resources -> Guild Templates
    #

    # Returns a guild template object for the given code.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/guild-template#get-guild-template)
    def get_guild_template(template_code : String)
      response = request(
        :guilds_templates_tc,
        nil,
        "GET",
        "/guilds/templates/#{template_code}",
        HTTP::Headers.new,
        nil
      )

      GuildTemplate.from_json(response.body)
    end

    # Create a new guild based on a template.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/guild-template#create-guild-from-guild-template)
    def create_guild_from_guild_template(template_code : String, name : String, icon : String? = nil)
      json = encode_tuple(
        name: name,
        icon: icon,
      )

      response = request(
        :guilds_templates_tc,
        nil,
        "POST",
        "/guilds/templates/#{template_code}",
        HTTP::Headers{"Content-Type" => "application/json"},
        json
      )

      Guild.from_json(response.body)
    end

    # Returns an array of guild template objects. Requires the "Manage Guild" permission.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/guild-template#get-guild-templates)
    def get_guild_templates(guild_id : UInt64 | Snowflake)
      response = request(
        :guilds_gid_templates,
        guild_id,
        "GET",
        "/guilds/#{guild_id}/templates",
        HTTP::Headers.new,
        nil
      )

      Array(GuildTemplate).from_json(response.body)
    end

    # Creates a template for the guild. Requires the "Manage Guild" permission.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/guild-template#create-guild-template)
    def create_guild_templates(guild_id : UInt64 | Snowflake, name : String, description : String? = nil)
      json = encode_tuple(
        name: name,
        description: description,
      )

      response = request(
        :guilds_gid_templates,
        guild_id,
        "POST",
        "/guilds/#{guild_id}/templates",
        HTTP::Headers{"Content-Type" => "application/json"},
        json
      )

      GuildTemplate.from_json(response.body)
    end

    # Syncs the template to the guild's current state. Requires the "Manage Guild" permission.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/guild-template#sync-guild-template)
    def sync_guild_templates(guild_id : UInt64 | Snowflake, template_code : String)
      response = request(
        :guilds_gid_templates_tc,
        guild_id,
        "PUT",
        "/guilds/#{guild_id}/templates/#{template_code}",
        HTTP::Headers.new,
        nil
      )

      GuildTemplate.from_json(response.body)
    end

    # Modifies the template's metadata. Requires the "Manage Guild" permission.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/guild-template#modify-guild-template)
    def modify_guild_templates(guild_id : UInt64 | Snowflake, template_code : String, name : String? = nil, description : String? = nil)
      json = encode_tuple(
        name: name,
        description: description,
      )

      response = request(
        :guilds_gid_templates_tc,
        guild_id,
        "PATCH",
        "/guilds/#{guild_id}/templates/#{template_code}",
        HTTP::Headers{"Content-Type" => "application/json"},
        json
      )

      GuildTemplate.from_json(response.body)
    end

    # Deletes the template. Requires the "Manage Guild" permission.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/guild-template#delete-guild-template)
    def delete_guild_templates(guild_id : UInt64 | Snowflake, template_code : String)
      response = request(
        :guilds_gid_templates_tc,
        guild_id,
        "DELETE",
        "/guilds/#{guild_id}/templates/#{template_code}",
        HTTP::Headers.new,
        nil
      )

      GuildTemplate.from_json(response.body)
    end

    #
    # Resources -> Invite
    #

    # Returns an invite object for the given code.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/invite#get-invite)
    def get_invite(code : String, with_counts : Bool? = nil, with_expiration : Bool? = nil)
      query = with_counts ? "?with_counts=#{with_counts}" : ""
      query += "&with_expiration=#{with_expiration}" if with_expiration
      query = "?#{query[1..]}" if query != "" && query[0] != '?'
      response = request(
        :invites,
        nil,
        "GET",
        "/invites/#{code}#{query}",
        HTTP::Headers.new,
        nil
      )

      Invite.from_json(response.body)
    end

    # Returns an invite object for the given code. Requires an "Manage Channels" or "Manage Guild" permission.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/invite#get-invite)
    def delete_invite(code : String)
      response = request(
        :invites,
        nil,
        "DELETE",
        "/invites/#{code}",
        HTTP::Headers.new,
        nil
      )

      Invite.from_json(response.body)
    end

    #
    # Resources -> Stage Instance
    #

    # Creates a new Stage instance associated to a Stage channel.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/stage-instance#create-stage-instance)
    def create_stage_instance(channel_id : UInt64 | Snowflake, topic : String, privacy_level : UInt8 | PrivacyLevel | Nil = PrivacyLevel::GuildOnly)
      json = encode_tuple(
        channel_id: channel_id,
        topic: topic,
        privacy_level: privacy_level,
      )

      response = request(
        :stageinstances,
        nil,
        "POST",
        "/stage-instances",
        HTTP::Headers{"Content-Type" => "application/json"},
        json
      )
    end

    # Gets the stage instance associated with the Stage channel, if it exists.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/stage-instance#get-stage-instance)
    def get_stage_instance(channel_id : UInt64 | Snowflake)
      response = request(
        :stageinstances_cid,
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
    def update_stage_instance(channel_id : UInt64 | Snowflake, topic : String? = nil, privacy_level : UInt8 | PrivacyLevel | Nil = nil)
      json = encode_tuple(
        topic: topic,
        privacy_level: privacy_level,
      )

      response = request(
        :stageinstances_cid,
        channel_id,
        "PATCH",
        "/stage-instances/#{channel_id}",
        HTTP::Headers{"Content-Type" => "application/json"},
        nil
      )
    end

    # Deletes the Stage instance.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/stage-instance#delete-stage-instance)
    def delete_stage_instance(channel_id : UInt64 | Snowflake)
      response = request(
        :stageinstances_cid,
        channel_id,
        "DELETE",
        "/stage-instances/#{channel_id}",
        HTTP::Headers.new,
        nil
      )
    end

    #
    # Resources -> User
    #

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
    def get_current_user_guilds(limit : Int32 = 100, before : UInt64 | Snowflake | Nil = nil, after : UInt64 | Snowflake | Nil = nil)
      params = URI::Params.build do |form|
        form.add "limit", limit.to_s
        form.add "before", before.to_s if before
        form.add "after", after.to_s if after
      end

      response = request(
        :users_me_guilds,
        nil,
        "GET",
        "/users/@me/guilds?#{params}",
        HTTP::Headers.new,
        nil
      )

      Array(PartialGuild).from_json(response.body)
    end

    # Returns a `Paginator` over the current users guilds.
    #
    # Will yield guilds in the given `direction` starting at `start_id` until
    # `limit` number of guilds are observed, or the user has no further guilds.
    # Setting `limit` to `nil` will have the paginator continue to make requests
    # until all guilds are fetched in the given `direction`.
    def page_current_user_guilds(start_id : UInt64 | Snowflake = 0_u64, limit : Int32? = 100, direction : Paginator::Direction = Paginator::Direction::Down, page_size : Int32 = 100)
      Paginator(PartialGuild).new(limit, direction) do |last_page|
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

    # Gets a list of DM channels the bot has access to.
    #
    # DEPRECATED: This method is not logner present in Discord documentation
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

    #
    # Resources -> Voice
    #

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

    #
    # Resources -> Webhook
    #

    # Create a new webhook. Requires the "Manage Webhooks" permission.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/webhook#create-webhook)
    def create_webhook(channel_id : UInt64 | Snowflake, name : String, avatar : String? = nil)
      json = encode_tuple(
        name: name,
        avatar: avatar,
      )

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

    # Get a webhook.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/webhook#get-webhook)
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

    # Modify a webhook. Accepts optional parameters `name`, `avatar`, and `channel_id`.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/webhook#modify-webhook).
    def modify_webhook(webhook_id : UInt64 | Snowflake, name : String? = nil, avatar : String? = nil,
                       channel_id : UInt64 | Snowflake | Nil = nil)
      json = encode_tuple(
        name: name,
        avatar: avatar,
        channel_id: channel_id,
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
        avatar: avatar,
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
                        embeds : Array(Embed)? = nil, file : String | IO | Nil = nil,
                        filename : String? = nil, tts : Bool? = nil, avatar_url : String? = nil,
                        username : String? = nil, allowed_mentions : AllowedMentions? = nil,
                        components : Array(Component)? = nil, wait : Bool? = false)
      body = encode_tuple(
        content: content,
        username: username,
        avatar_url: avatar_url,
        tts: tts,
        embeds: embeds,
        allowed_mentions: allowed_mentions,
        components: components,
      )

      content_type = "application/json"
      body, content_type = send_file(body, file, filename) if file

      response = request(
        :webhooks_wid,
        webhook_id,
        "POST",
        "/webhooks/#{webhook_id}/#{token}#{wait ? "?wait=#{wait}" : ""}",
        HTTP::Headers{"Content-Type" => content_type},
        body
      )

      # Expecting response
      Message.from_json(response.body) if wait
    end

    # Returns a previously-sent webhook message from the same token.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/webhook#get-webhook-message)
    def get_webhook_message(webhook_id : UInt64 | Snowflake, token : String, message_id : UInt64 | Snowflake)
      response = request(
        :webhooks_wid_t_messages_mid,
        webhook_id,
        "GET",
        "/webhooks/#{webhook_id}/#{token}/messages/#{message_id}",
        HTTP::Headers.new,
        nil
      )

      Message.from_json(response.body)
    end

    # Edits a previously-sent webhook message from the same token.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/webhook#get-webhook-message)
    def edit_webhook_message(webhook_id : UInt64 | Snowflake, token : String, message_id : UInt64 | Snowflake,
                             content : String? = nil, embeds : Array(Embed)? = nil,
                             file : String | IO | Nil = nil, filename : String? = nil,
                             allowed_mentions : AllowedMentions? = nil, components : Array(Component)? = nil)
      body = encode_tuple(
        content: content,
        embeds: embeds,
        allowed_mentions: allowed_mentions,
        components: components,
      )

      content_type = "application/json"
      body, content_type = send_file(body, file, filename) if file

      response = request(
        :webhooks_wid_t_messages_mid,
        webhook_id,
        "PATCH",
        "/webhooks/#{webhook_id}/#{token}/messages/#{message_id}",
        HTTP::Headers{"Content-Type" => content_type},
        body
      )

      Message.from_json(response.body)
    end

    # Deletes a message that was created by the webhook.
    #
    # [API docs for this method](https://discord.com/developers/docs/resources/webhook#delete-webhook-message)
    def delete_webhook_message(webhook_id : UInt64 | Snowflake, token : String, message_id : UInt64 | Snowflake)
      response = request(
        :webhooks_wid_t_messages_mid,
        webhook_id,
        "DELETE",
        "/webhooks/#{webhook_id}/#{token}/messages/#{message_id}",
        HTTP::Headers.new,
        nil
      )
    end

    #
    # Interactions -> Slash Commands
    #

    # Fetch all of the global commands for your application.
    #
    # [API docs for this method](https://discord.com/developers/docs/interactions/slash-commands#get-global-application-commands)
    def get_global_application_commands(application_id : UInt64 | Snowflake)
      response = request(
        :applications_aid_commands,
        application_id,
        "GET",
        "/applications/#{application_id}/commands",
        HTTP::Headers.new,
        nil
      )

      Array(ApplicationCommand).from_json(response.body)
    end

    # Create a new global command. New global commands will be available in all guilds after 1 hour.
    #
    # [API docs for this method](https://discord.com/developers/docs/interactions/slash-commands#create-global-application-command)
    def create_global_application_command(application_id : UInt64 | Snowflake, name : String, description : String,
                                          options : Array(ApplicationCommandOption)? = nil, default_permission : Bool? = nil)
      json = encode_tuple(
        name: name,
        description: description,
        options: options,
        default_permission: default_permission,
      )

      response = request(
        :applications_aid_commands,
        application_id,
        "POST",
        "/applications/#{application_id}/commands",
        HTTP::Headers{"Content-Type" => "application/json"},
        json
      )

      ApplicationCommand.from_json(response.body)
    end

    # Fetch a global command for your application.
    #
    # [API docs for this method](https://discord.com/developers/docs/interactions/slash-commands#get-global-application-command)
    def get_global_application_command(application_id : UInt64 | Snowflake, command_id : UInt64 | Snowflake)
      response = request(
        :applications_aid_commands_cid,
        application_id,
        "GET",
        "/applications/#{application_id}/commands/#{command_id}",
        HTTP::Headers.new,
        nil
      )

      ApplicationCommand.from_json(response.body)
    end

    # Edit a global command. Updates will be available in all guilds after 1 hour.
    #
    # [API docs for this method](https://discord.com/developers/docs/interactions/slash-commands#edit-global-application-command)
    def edit_global_application_command(application_id : UInt64 | Snowflake, command_id : UInt64 | Snowflake,
                                        name : String? = nil, description : String? = nil,
                                        options : Array(ApplicationCommandOption)? = nil, default_permission : Bool? = nil)
      json = encode_tuple(
        name: name,
        description: description,
        options: options,
        default_permission: default_permission,
      )

      response = request(
        :applications_aid_commands_cid,
        application_id,
        "PATCH",
        "/applications/#{application_id}/commands/#{command_id}",
        HTTP::Headers{"Content-Type" => "application/json"},
        json
      )

      ApplicationCommand.from_json(response.body)
    end

    # Deletes a global command.
    #
    # [API docs for this method](https://discord.com/developers/docs/interactions/slash-commands#delete-global-application-command)
    def delete_global_application_command(application_id : UInt64 | Snowflake, command_id : UInt64 | Snowflake)
      response = request(
        :applications_aid_commands_cid,
        application_id,
        "DELETE",
        "/applications/#{application_id}/commands/#{command_id}",
        HTTP::Headers.new,
        nil
      )
    end

    # Fetch all of the guild commands for your application for a specific guild.
    #
    # [API docs for this method](https://discord.com/developers/docs/interactions/slash-commands#get-guild-application-commands)
    def get_guild_application_commands(application_id : UInt64 | Snowflake, guild_id : UInt64 | Snowflake)
      response = request(
        :applications_aid_guilds_gid_commands,
        application_id,
        "GET",
        "/applications/#{application_id}/guilds/#{guild_id}/commands",
        HTTP::Headers.new,
        nil
      )

      Array(ApplicationCommand).from_json(response.body)
    end

    # Takes a list of application commands, overwriting existing commands that are registered globally for this application. Updates will be available in all guilds after 1 hour.
    #
    # [API docs for this method](https://discord.com/developers/docs/interactions/slash-commands#bulk-overwrite-global-application-commands)
    def bulk_overwrite_global_application_commands(application_id : UInt64 | Snowflake, commands : Array(PartialApplicationCommand))
      response = request(
        :applications_aid_commands,
        application_id,
        "PUT",
        "/applications/#{application_id}/commands",
        HTTP::Headers{"Content-Type" => "application/json"},
        commands.to_json
      )

      Array(ApplicationCommand).from_json(response.body)
    end

    # Create a new guild command. New guild commands will be available in the guild immediately.
    #
    # [API docs for this method](https://discord.com/developers/docs/interactions/slash-commands#create-guild-application-command)
    def create_guild_application_command(application_id : UInt64 | Snowflake, guild_id : UInt64 | Snowflake, name : String, description : String,
                                         options : Array(ApplicationCommandOption)? = nil, default_permission : Bool? = nil)
      json = encode_tuple(
        name: name,
        description: description,
        options: options,
        default_permission: default_permission,
      )

      response = request(
        :applications_aid_guilds_gid_commands,
        application_id,
        "POST",
        "/applications/#{application_id}/guilds/#{guild_id}/commands",
        HTTP::Headers{"Content-Type" => "application/json"},
        json
      )

      ApplicationCommand.from_json(response.body)
    end

    # Fetch a guild command for your application.
    #
    # [API docs for this method](https://discord.com/developers/docs/interactions/slash-commands#get-guild-application-command)
    def get_guild_application_command(application_id : UInt64 | Snowflake, guild_id : UInt64 | Snowflake, command_id : UInt64 | Snowflake)
      response = request(
        :applications_aid_guilds_gid_commands_cid,
        application_id,
        "GET",
        "/applications/#{application_id}/guilds/#{guild_id}/commands/#{command_id}",
        HTTP::Headers.new,
        nil
      )

      ApplicationCommand.from_json(response.body)
    end

    # Edit a guild command. Updates for guild commands will be available immediately.
    #
    # [API docs for this method](https://discord.com/developers/docs/interactions/slash-commands#edit-guild-application-command)
    def edit_guild_application_command(application_id : UInt64 | Snowflake, guild_id : UInt64 | Snowflake, command_id : UInt64 | Snowflake,
                                       name : String? = nil, description : String? = nil,
                                       options : Array(ApplicationCommandOption)? = nil, default_permission : Bool? = nil)
      json = encode_tuple(
        name: name,
        description: description,
        options: options,
        default_permission: default_permission,
      )

      response = request(
        :applications_aid_guilds_gid_commands_cid,
        application_id,
        "PATCH",
        "/applications/#{application_id}/guilds/#{guild_id}/commands/#{command_id}",
        HTTP::Headers{"Content-Type" => "application/json"},
        json
      )

      ApplicationCommand.from_json(response.body)
    end

    # Delete a guild command.
    #
    # [API docs for this method](https://discord.com/developers/docs/interactions/slash-commands#delete-guild-application-command)
    def delete_guild_application_command(application_id : UInt64 | Snowflake, guild_id : UInt64 | Snowflake, command_id : UInt64 | Snowflake)
      response = request(
        :applications_aid_guilds_gid_commands_cid,
        application_id,
        "DELETE",
        "/applications/#{application_id}/guilds/#{guild_id}/commands/#{command_id}",
        HTTP::Headers.new,
        nil
      )
    end

    # Takes a list of application commands, overwriting existing commands for the guild.
    #
    # [API docs for this method](https://discord.com/developers/docs/interactions/slash-commands#bulk-overwrite-guild-application-commands)
    def bulk_overwrite_guild_application_command(application_id : UInt64 | Snowflake, guild_id : UInt64 | Snowflake, commands : Array(PartialApplicationCommand))
      response = request(
        :applications_aid_guilds_gid_commands,
        application_id,
        "PUT",
        "/applications/#{application_id}/guilds/#{guild_id}/commands",
        HTTP::Headers{"Content-Type" => "application/json"},
        commands.to_json
      )

      Array(ApplicationCommand).from_json(response.body)
    end

    # Create a response to an Interaction from the gateway.
    #
    # [API docs for this method](https://discord.com/developers/docs/interactions/slash-commands#create-interaction-response)
    def create_interaction_response(interaction_id : UInt64 | Snowflake, token : String, response : InteractionResponse)
      response = request(
        :interactions_iid_t_callback,
        interaction_id,
        "POST",
        "/interactions/#{interaction_id}/#{token}/callback",
        HTTP::Headers{"Content-Type" => "application/json"},
        response.to_json
      )
    end

    # Returns the initial Interaction response.
    #
    # [API docs for this method](https://discord.com/developers/docs/interactions/slash-commands#get-original-interaction-response)
    def get_original_interaction_response(application_id : UInt64 | Snowflake, token : String)
      response = request(
        :webhooks_aid_t_messages_original,
        application_id,
        "GET",
        "/webhooks/#{application_id}/#{token}/messages/@original",
        HTTP::Headers.new,
        nil
      )

      Message.from_json(response.body)
    end

    # Edits the initial Interaction response.
    #
    # [API docs for this method](https://discord.com/developers/docs/interactions/slash-commands#edit-original-interaction-response)
    def edit_original_interaction_response(application_id : UInt64 | Snowflake, token : String,
                                           content : String? = nil, embeds : Array(Embed)? = nil,
                                           file : String | IO | Nil = nil, filename : String? = nil,
                                           allowed_mentions : AllowedMentions? = nil, components : Array(Component)? = nil)
      body = encode_tuple(
        content: content,
        embeds: embeds,
        allowed_mentions: allowed_mentions,
        components: components,
      )

      content_type = "application/json"
      body, content_type = send_file(body, file, filename) if file

      response = request(
        :webhooks_aid_t_messages_original,
        application_id,
        "PATCH",
        "/webhooks/#{application_id}/#{token}/messages/@original",
        HTTP::Headers{"Content-Type" => content_type},
        body
      )

      Message.from_json(response.body)
    end

    # Deletes the initial Interaction response.
    #
    # [API docs for this method](https://discord.com/developers/docs/interactions/slash-commands#delete-original-interaction-response)
    def delete_original_interaction_response(application_id : UInt64 | Snowflake, token : String)
      response = request(
        :webhooks_aid_t_messages_original,
        application_id,
        "DELETE",
        "/webhooks/#{application_id}/#{token}/messages/@original",
        HTTP::Headers.new,
        nil
      )
    end

    # Create a followup message for an Interaction.
    #
    # [API docs for this method](https://discord.com/developers/docs/interactions/slash-commands#create-followup-message)
    def create_followup_message(application_id : UInt64 | Snowflake, token : String, content : String? = nil,
                                embeds : Array(Embed)? = nil, file : String | IO | Nil = nil,
                                filename : String? = nil, tts : Bool? = nil, avatar_url : String? = nil,
                                username : String? = nil, allowed_mentions : AllowedMentions? = nil,
                                components : Array(Component)? = nil, wait : Bool? = false)
      execute_webhook(application_id, token, content, file, filename, embeds, tts, nil, nil, allowed_mentions, components, true)
    end

    # Edits a followup message for an Interaction.
    #
    # [API docs for this method](https://discord.com/developers/docs/interactions/slash-commands#edit-followup-message)
    def edit_followup_message(application_id : UInt64 | Snowflake, token : String, message_id : UInt64 | Snowflake,
                              content : String? = nil, embeds : Array(Embed)? = nil,
                              file : String | IO | Nil = nil, filename : String? = nil,
                              allowed_mentions : AllowedMentions? = nil, components : Array(Component)? = nil)
      edit_webhook_message(application_id, token, message_id, file, filename, content, embeds, allowed_mentions, components)
    end

    # Deletes a followup message for an Interaction.
    #
    # [API docs for this method](https://discord.com/developers/docs/interactions/slash-commands#delete-followup-message)
    def delete_followup_message(application_id : UInt64 | Snowflake, token : String, message_id : UInt64 | Snowflake)
      response = request(
        :webhooks_aid_t_messages_mid,
        application_id,
        "DELETE",
        "/webhooks/#{application_id}/#{token}/messages/#{message_id}",
        HTTP::Headers.new,
        nil
      )
    end

    # Fetches command permissions for all commands for your application in a guild.
    #
    # [API docs for this method](https://discord.com/developers/docs/interactions/slash-commands#get-guild-application-command-permissions)
    def get_guild_application_command_permissions(application_id : UInt64 | Snowflake, guild_id : UInt64 | Snowflake)
      response = request(
        :applications_aid_guilds_gid_commands_permissions,
        application_id,
        "GET",
        "/applications/#{application_id}/guilds/#{guild_id}/commands/permissions",
        HTTP::Headers.new,
        nil
      )

      Array(GuildApplicationCommandPermissions).from_json(response.body)
    end

    # Fetches command permissions for a specific command for your application in a guild.
    #
    # [API docs for this method](https://discord.com/developers/docs/interactions/slash-commands#get-application-command-permissions)
    def get_application_command_permissions(application_id : UInt64 | Snowflake, guild_id : UInt64 | Snowflake, command_id : UInt64 | Snowflake)
      response = request(
        :applications_aid_guilds_gid_commands_cid_permissions,
        application_id,
        "GET",
        "/applications/#{application_id}/guilds/#{guild_id}/commands/#{command_id}/permissions",
        HTTP::Headers.new,
        nil
      )

      GuildApplicationCommandPermissions.from_json(response.body)
    end

    # Edits command permissions for a specific command for your application in a guild. You can only add up to 10 permission overwrites for a command.
    #
    # NOTE: This endpoint will overwrite existing permissions for the command in that guild
    #
    # [API docs for this method](https://discord.com/developers/docs/interactions/slash-commands#edit-application-command-permissions)
    def edit_application_command_permissions(application_id : UInt64 | Snowflake, guild_id : UInt64 | Snowflake, command_id : UInt64 | Snowflake, permissions : Array(ApplicationCommandPermissions))
      response = request(
        :applications_aid_guilds_gid_commands_cid_permissions,
        application_id,
        "PUT",
        "/applications/#{application_id}/guilds/#{guild_id}/commands/#{command_id}/permissions",
        HTTP::Headers{"Content-Type" => "application/json"},
        {permissions: permissions}.to_json
      )
    end

    # Batch edits permissions for all commands in a guild. Takes an array of partial GuildApplicationCommandPermissions objects including id and permissions.
    # You can only add up to 10 permission overwrites for a command.
    #
    # NOTE: This endpoint will overwrite all existing permissions for all commands in a guild
    #
    # [API docs for this method](https://discord.com/developers/docs/interactions/slash-commands#batch-edit-application-command-permissions)
    def batch_edit_application_command_permissions(application_id : UInt64 | Snowflake, guild_id : UInt64 | Snowflake, permissions : Hash(UInt64 | Snowflake, Array(ApplicationCommandPermissions)))
      json = permissions.map { |cid, perm| {"id" => cid, "permissions" => perm} }
      response = request(
        :applications_aid_guilds_gid_commands_permissions,
        application_id,
        "PUT",
        "/applications/#{application_id}/guilds/#{guild_id}/commands/permissions",
        HTTP::Headers{"Content-Type" => "application/json"},
        json.to_json
      )
    end
  end
end
