require "./mappings/*"

module Discord
  # A cache is a utility class that stores various kinds of Discord objects,
  # like `User`s, `Role`s etc. Its purpose is to reduce both the load on
  # Discord's servers and reduce the latency caused by having to do an API call.
  # It is recommended to use caching for bots that interact heavily with
  # Discord-provided data, like for example administration bots, as opposed to
  # bots that only interact by sending and receiving messages. For that latter
  # kind, caching is usually even counter-productive as it only unnecessarily
  # increases memory usage.
  #
  # Caching can either be used standalone, in a purely REST-based way:
  # ```
  # client = Discord::Client.new(token: "Bot token", client_id: 123_u64)
  # cache = Discord::Cache.new(client)
  #
  # puts cache.resolve_user(66237334693085184) # will perform API call
  # puts cache.resolve_user(66237334693085184) # will not perform an API call, as the data is now cached
  # ```
  #
  # It can also be integrated more deeply into a `Client` (specifically one that
  # uses a gateway connection) to reduce cache misses even more by automatically
  # caching data received over the gateway:
  # ```
  # client = Discord::Client.new(token: "Bot token", client_id: 123_u64)
  # cache = Discord::Cache.new(client)
  # client.cache = cache # Integrate the cache into the client
  # ```
  #
  # Note that if a cache is *not* used this way, its data will slowly go out of
  # sync with Discord, and unless it is used in an environment with few changes
  # likely to occur, a client without a gateway connection should probably
  # refrain from caching at all.
  class Cache
    # A map of cached users. These aren't necessarily all the users in servers
    # the bot has access to, but rather all the users that have been seen by
    # the bot in the past (and haven't been deleted by means of `delete_user`).
    getter users

    # A map of cached channels, i. e. all channels on all servers the bot is on,
    # as well as all DM channels.
    getter channels

    # A map of guilds (servers) the bot is on. Doesn't ignore guilds temporarily
    # deleted due to an outage; so if an outage is going on right now the
    # affected guilds would be missing here too.
    getter guilds

    # A map of cached scheduled events, i.e. all scheduled events on all servers
    # the bot is on.
    getter scheduled_events
    
    # A map of cached stage instances, i. e. all stage instances on all servers
    # the bot is on.
    getter stage_instances

    # A double map of members on servers, represented as {guild ID => {user ID
    # => member}}. Will only contain previously and currently online members as
    # well as all members that have been chunked (see
    # `Client#request_guild_members`).
    getter members

    # A map of all roles on servers the bot is on. Does not discriminate by
    # guild, as role IDs are unique even across guilds.
    getter roles

    # Mapping of users to the respective DM channels the bot has open with them,
    # represented as {user ID => channel ID}.
    getter dm_channels

    # Mapping of guilds to the roles on them, represented as {guild ID =>
    # [role IDs]}.
    getter guild_roles

    # Mapping of guilds to the channels on them, represented as {guild ID =>
    # [channel IDs]}.
    getter guild_channels

    # Mapping of guilds to the scheduled events on them, represented as {guild ID =>
    # [scheduled event IDs]}.
    getter guild_scheduled_events

    # Mapping of guild scheduled event to the users subscribed to them, represented as
    # {guild scheduled event ID => [user IDs]}.
    getter guild_scheduled_event_users

    # Mapping of guilds to the Stage instances on them, represented as {guild ID =>
    # [stage instance IDs]}.
    getter guild_stage_instances

    # Mapping of users in guild to voice states, represented as {guild ID =>
    # {user ID => voice state}}
    getter voice_states

    # Creates a new cache with a *client* that requests (in case of cache
    # misses) should be done on.
    def initialize(@client : Client)
      @users = Hash(UInt64, User).new
      @channels = Hash(UInt64, Channel).new
      @guilds = Hash(UInt64, Guild).new
      @members = Hash(UInt64, Hash(UInt64, GuildMember)).new
      @roles = Hash(UInt64, Role).new
      @scheduled_events = Hash(UInt64, GuildScheduledEvent).new
      @stage_instances = Hash(UInt64, StageInstance).new

      @dm_channels = Hash(UInt64, UInt64).new

      @guild_roles = Hash(UInt64, Array(UInt64)).new
      @guild_channels = Hash(UInt64, Array(UInt64)).new
      @guild_scheduled_events = Hash(UInt64, Array(UInt64)).new
      @guild_scheduled_event_users = Hash(UInt64, Array(UInt64)).new
      @guild_stage_instances = Hash(UInt64, Array(UInt64)).new

      @voice_states = Hash(UInt64, Hash(UInt64, VoiceState)).new
    end

    # Resolves a user by its *ID*. If the requested object is not cached, it
    # will do an API call.
    def resolve_user(id : UInt64 | Snowflake) : User
      id = id.to_u64
      @users.fetch(id) { @users[id] = @client.get_user(id) }
    end

    # Resolves a channel by its *ID*. If the requested object is not cached, it
    # will do an API call.
    def resolve_channel(id : UInt64 | Snowflake) : Channel
      id = id.to_u64
      @channels.fetch(id) { @channels[id] = @client.get_channel(id) }
    end

    # Resolves a guild by its *ID*. If the requested object is not cached, it
    # will do an API call.
    def resolve_guild(id : UInt64 | Snowflake) : Guild
      id = id.to_u64
      @guilds.fetch(id) { @guilds[id] = @client.get_guild(id) }
    end

    # Resolves a member by the *guild_id* of the guild the member is on, and the
    # *user_id* of the member itself. An API request will be performed if the
    # object is not cached.
    def resolve_member(guild_id : UInt64 | Snowflake, user_id : UInt64 | Snowflake) : GuildMember
      guild_id = guild_id.to_u64
      user_id = user_id.to_u64
      local_members = @members[guild_id] ||= Hash(UInt64, GuildMember).new
      local_members.fetch(user_id) { local_members[user_id] = @client.get_guild_member(guild_id, user_id) }
    end

    # Resolves a role by its *ID*. No API request will be performed if the role
    # is not cached, because there is no endpoint for individual roles; however
    # all roles should be cached at all times so it won't be a problem.
    def resolve_role(id : UInt64 | Snowflake) : Role
      @roles[id.to_u64] # There is no endpoint for getting an individual role, so we will have to ignore that case for now.
    end

    # Resolves a guild scheduled event by the *guild_id* of the guild the scheduled
    # event is on, and the *event_id* of the event itself. An API request will be performed
    # if the object is not cached.
    def resolve_guild_scheduled_event(guild_id : UInt64 | Snowflake, event_id : UInt64 | Snowflake) : GuildScheduledEvent
      guild_id = guild_id.to_u64
      event_id = event_id.to_u64
      @scheduled_events.fetch(event_id) do
        event = @client.get_guild_scheduled_event(guild_id, event_id)
        cache(event)
        add_guild_scheduled_event(event.guild_id, event.id)
        event
      end
    end

    # Resolves an array of users by the *guild_id* of the guild the  guild scheduled event
    # is on, and the *event_id* of the event itself. API requests will be performed
    # if the object is not cached. If a limit is provided, the subscribed users will
    # only be cached if the number of users is below the limit, to ensure it remains synced.
    # User and member data is cached regardless. Member data is included if *with_member* is true. 
    def resolve_guild_scheduled_event_users(guild_id : UInt64 | Snowflake, event_id : UInt64 | Snowflake,
                                            with_member : Bool? = nil, limit : Int32? = nil) : Array(UInt64)
      guild_id = guild_id.to_u64
      event_id = event_id.to_u64
      @guild_scheduled_event_users.fetch(event_id) do
        users = @client.page_guild_scheduled_event_users(guild_id, event_id, with_member: with_member, limit: limit).to_a
        
        users.each do |user|
          cache user.user
          if member = user.member
            cache member, guild_id
          end
        end
        return users.map &.user.id.to_u64 if users.size == limit
        @guild_scheduled_event_users[event_id] = users.map &.user.id.to_u64
      end
    end

    # Resolves a Stage instance by its *ID*.
    # An API request will be performed if the object is not cached.
    def resolve_stage_instance(id : UInt64 | Snowflake) : StageInstance
      id = id.to_u64
      @stage_instances.fetch(id) { @stage_instances[id] = @client.get_stage_instance(id) }
    end

    # Resolves the ID of a DM channel with a particular user by the recipient's
    # *recipient_id*. If there is no such channel cached, one will be created.
    def resolve_dm_channel(recipient_id : UInt64 | Snowflake) : UInt64
      recipient_id = recipient_id.to_u64
      @dm_channels.fetch(recipient_id) do
        channel = @client.create_dm(recipient_id)
        cache(Channel.new(channel))
        @dm_channels[recipient_id] = channel.id.to_u64
      end
    end

    # Resolves the current user's profile. Requires no parameters since the
    # endpoint has none either. If there is a gateway connection this should
    # always be cached.
    def resolve_current_user : User
      @current_user ||= @client.get_current_user
    end

    # Resolves a voice state by *guild ID* and *user ID*. No API request will be
    # performed if voice state is not cached, because there is no endpoint for
    # it. If there is a gateway connection this should always be cached.
    def resolve_voice_state(guild_id : UInt64 | Snowflake, user_id : UInt64 | Snowflake) : VoiceState
      @voice_states[guild_id.to_u64][user_id.to_u64]
    end

    # Deletes a user from the cache given its *ID*.
    def delete_user(id : UInt64 | Snowflake)
      @users.delete(id.to_u64)
    end

    # Deletes a channel from the cache given its *ID*.
    def delete_channel(id : UInt64 | Snowflake)
      @channels.delete(id.to_u64)
    end

    # Deletes a guild from the cache given its *ID*.
    def delete_guild(id : UInt64 | Snowflake)
      @guilds.delete(id.to_u64)
    end

    def delete_scheduled_event(id : UInt64 | Snowflake)
      @scheduled_events.delete(id.to_u64)
    end

    # Deletes a stage instance from the cache given its *ID*.
    def delete_stage_instance(id : UInt64 | Snowflake)
      @stage_instances.delete(id.to_u64)
    end

    # Deletes a member from the cache given its *user_id* and the *guild_id* it
    # is on.
    def delete_member(guild_id : UInt64 | Snowflake, user_id : UInt64 | Snowflake)
      guild_id = guild_id.to_u64
      user_id = user_id.to_u64
      @members[guild_id]?.try &.delete(user_id)
    end

    # Deletes a role from the cache given its *ID*.
    def delete_role(id : UInt64 | Snowflake)
      @roles.delete(id.to_u64)
    end

    # Deletes a DM channel with a particular user given the *recipient_id*.
    def delete_dm_channel(recipient_id : UInt64 | Snowflake)
      @dm_channels.delete(recipient_id.to_u64)
    end

    # Deletes the current user from the cache, if that will ever be necessary.
    def delete_current_user
      @current_user = nil
    end

    # Deletes voice state for user in guild from cache.
    def delete_voice_state(guild_id : UInt64 | Snowflake, user_id : UInt64 | Snowflake)
      guild_id = guild_id.to_u64
      user_id = user_id.to_u64
      @voice_states[guild_id]?.try &.delete(user_id)
    end

    # Adds a specific *user* to the cache.
    def cache(user : User)
      @users[user.id.to_u64] = user
    end

    # Adds a specific *channel* to the cache.
    def cache(channel : Channel)
      @channels[channel.id.to_u64] = channel
    end

    # Adds a specific *guild* to the cache.
    def cache(guild : Guild)
      @guilds[guild.id.to_u64] = guild
    end

    # Adds a specific *member* to the cache, given the *guild_id* it is on.
    def cache(member : GuildMember, guild_id : UInt64 | Snowflake)
      guild_id = guild_id.to_u64
      local_members = @members[guild_id] ||= Hash(UInt64, GuildMember).new
      local_members[member.user.id.to_u64] = member
    end

    # Adds a specific *role* to the cache.
    def cache(role : Role)
      @roles[role.id.to_u64] = role
    end

    # Adds a specific *guild scheduled event* to the cache.
    def cache(guild_scheduled_event : GuildScheduledEvent)
      @scheduled_events[guild_scheduled_event.id.to_u64] = guild_scheduled_event
    end

    # Adds a specific *Stage instance* to the cache.
    def cache(stage_instance : StageInstance)
      @stage_instances[stage_instance.id.to_u64] = stage_instance
    end

    # Adds a specific *voice state* to the cache.
    def cache(voice_state : VoiceState)
      user_id = voice_state.user_id.to_u64
      guild_id = voice_state.guild_id.not_nil!.to_u64
      user_voice_states = @voice_states[guild_id] ||= Hash(UInt64, VoiceState).new
      user_voice_states[user_id] = voice_state
    end

    # Adds a particular DM channel to the cache, given the *channel_id* and the
    # *recipient_id*.
    def cache_dm_channel(channel_id : UInt64 | Snowflake, recipient_id : UInt64 | Snowflake)
      channel_id = channel_id.to_u64
      recipient_id = recipient_id.to_u64
      @dm_channels[recipient_id] = channel_id
    end

    # Caches the current user.
    def cache_current_user(@current_user : User); end

    # Adds multiple *members* at once to the cache, given the *guild_id* they
    # all share. This method exists to slightly reduce the overhead of
    # processing chunks; outside of that it is likely not of much use.
    def cache_multiple_members(members : Array(GuildMember), guild_id : UInt64 | Snowflake)
      guild_id = guild_id.to_u64
      local_members = @members[guild_id] ||= Hash(UInt64, GuildMember).new
      members.each do |member|
        local_members[member.user.id.to_u64] = member
      end
    end

    # Returns all roles of a guild, identified by its *guild_id*.
    def guild_roles(guild_id : UInt64 | Snowflake) : Array(UInt64)
      @guild_roles[guild_id.to_u64]
    end

    # Marks a role, identified by the *role_id*, as belonging to a particular
    # guild, identified by the *guild_id*.
    def add_guild_role(guild_id : UInt64 | Snowflake, role_id : UInt64 | Snowflake)
      guild_id = guild_id.to_u64
      role_id = role_id.to_u64
      local_roles = @guild_roles[guild_id] ||= [] of UInt64
      local_roles << role_id
    end

    # Marks a role as not belonging to a particular guild anymore.
    def remove_guild_role(guild_id : UInt64 | Snowflake, role_id : UInt64 | Snowflake)
      guild_id = guild_id.to_u64
      role_id = role_id.to_u64
      @guild_roles[guild_id]?.try { |local_roles| local_roles.delete(role_id) }
    end

    # Returns all channels of a guild, identified by its *guild_id*.
    def guild_channels(guild_id : UInt64 | Snowflake) : Array(UInt64)
      @guild_channels[guild_id.to_u64]
    end

    # Marks a channel, identified by the *channel_id*, as belonging to a particular
    # guild, identified by the *guild_id*.
    def add_guild_channel(guild_id : UInt64 | Snowflake, channel_id : UInt64 | Snowflake)
      guild_id = guild_id.to_u64
      channel_id = channel_id.to_u64
      local_channels = @guild_channels[guild_id] ||= [] of UInt64
      local_channels << channel_id
    end

    # Marks a channel as not belonging to a particular guild anymore.
    def remove_guild_channel(guild_id : UInt64 | Snowflake, channel_id : UInt64 | Snowflake)
      guild_id = guild_id.to_u64
      channel_id = channel_id.to_u64
      @guild_channels[guild_id]?.try { |local_channels| local_channels.delete(channel_id) }
    end

    # Returns all guild scheduled events, identified by the guild's *guild_id*.
    def guild_scheduled_events(guild_id : UInt64 | Snowflake) : Array(UInt64)
      @guild_scheduled_events[guild_id.to_u64]
    end

    # Marks a guild scheduled event, identified by the *event_id*, as belonging to a particular
    # guild, identified by the *guild_id*.
    def add_guild_scheduled_event(guild_id : UInt64 | Snowflake, event_id : UInt64 | Snowflake)
      local_events = @guild_scheduled_events[guild_id.to_u64] ||= [] of UInt64
      local_events << event_id.to_u64
    end

    # Marks a guild scheduled event, identified by the *event_id*, as belonging to a particular
    # guild, identified by the *guild_id*. This should only be called when the event is created
    # during a websocket connection, not a GUILD_CREATE, otherwise the event users cache will be out of sync.
    def create_guild_scheduled_event(guild_id : UInt64 | Snowflake, event_id : UInt64 | Snowflake)
      add_guild_scheduled_event(guild_id, event_id)
      @guild_scheduled_event_users[event_id.to_u64] = [] of UInt64
    end

    # Marks a guild scheduled event, identified by the *event_id*, as not belonging to a particular guild,
    # identified by its *guild_id*, anymore.
    def remove_guild_scheduled_event(guild_id : UInt64 | Snowflake, event_id : UInt64 | Snowflake)
      @guild_scheduled_events[guild_id.to_u64]?.try { |local_events| local_events.delete(event_id.to_u64) }
    end

    # Returns all guild scheduled event users, identified by its *event_id*.
    def guild_scheduled_event_users(event_id : UInt64 | Snowflake) : Array(UInt64)
      @guild_scheduled_event_users[event_id.to_u64]
    end

    # Marks a user, identified by the *user_id*, as subscribed to a particular guild scheduled event,
    # identified by the *event_id*.
    def add_guild_scheduled_event_user(event_id : UInt64 | Snowflake, user_id : UInt64 | Snowflake)
      @guild_scheduled_event_users[event_id.to_u64]?.try { |local_event_users| local_event_users << user_id.to_u64 }
    end

    # Marks a user, identified by the *user_id*, as unsubscribed to a particular guild scheduled event,
    # identified by the *event_id*.
    def remove_guild_scheduled_event_user(event_id : UInt64 | Snowflake, user_id : UInt64 | Snowflake)
      @guild_scheduled_event_users[event_id.to_u64]?.try { |local_event_users| local_event_users.delete(user_id.to_u64) }
    end

    # Returns all Stage instances of a guild, identified by its *guild_id*.
    def guild_stage_instances(guild_id : UInt64 | Snowflake) : Array(UInt64)
      @guild_stage_instances[guild_id.to_u64]
    end

    # Marks a Stage instance, identified by the *instance_id*, as belonging to a particular
    # guild, identified by the *guild_id*.
    def add_guild_stage_instance(guild_id : UInt64 | Snowflake, instance_id : UInt64 | Snowflake)
      guild_id = guild_id.to_u64
      instance_id = instance_id.to_u64
      local_instances = @guild_stage_instances[guild_id] ||= [] of UInt64
      local_instances << instance_id
    end

    # Marks a Stage instance as not belonging to a particular guild anymore.
    def remove_guild_stage_instance(guild_id : UInt64 | Snowflake, instance_id : UInt64 | Snowflake)
      guild_id = guild_id.to_u64
      instance_id = instance_id.to_u64
      @guild_stage_instances[guild_id]?.try { |local_instances| local_instances.delete(instance_id) }
    end
  end
end
