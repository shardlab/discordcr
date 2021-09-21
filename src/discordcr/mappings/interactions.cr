require "./converters"

module Discord
  enum InteractionType : UInt8
    Ping               = 1
    ApplicationCommand = 2
    MessageComponent   = 3
  end

  struct Interaction
    include JSON::Serializable

    property id : Snowflake
    property application_id : Snowflake
    @[JSON::Field(converter: Enum::ValueConverter(Discord::InteractionType))]
    property type : InteractionType
    property data : InteractionData?
    property guild_id : Snowflake?
    property channel_id : Snowflake?
    property member : GuildMember?
    property user : User?
    property token : String
    property version : Int32
    property message : Message?

    # Returns the interaction data within `#data` variable associated with `InteractionType::ApplicationCommand` interaction type, and unwraps nilable variables if possible.
    #
    # Since `InteractionData` is used for different interaction types with different choice of fields, all its variables are nilable by default, but we can ensure some non-nil variables if we know the type of the interaction.
    def application_command_data
      data = @data.not_nil! # data is always present for this interaction type
      {
        id: data.id.not_nil!,
        name: data.name.not_nil!,
        type: data.type.not_nil!,
        resolved: data.resolved,
        options: data.options,
        target_id: data.target_id
      }
    end

    # Returns the interaction data within `#data` variable associated with `InteractionType::MessageComponent` interaction type, and unwraps nilable variables if possible.
    #
    # Since `InteractionData` is used for different interaction types with different choice of fields, all its variables are nilable by default, but we can ensure some non-nil variables if we know the type of the interaction.
    def message_component_data
      data = @data.not_nil! # data is always present for this interaction type
      {
        custom_id: data.custom_id.not_nil!,
        component_type: data.component_type.not_nil!,
        values: data.values
      }
    end
  end

  struct InteractionData
    include JSON::Serializable

    property id : Snowflake?
    property name : String?
    @[JSON::Field(converter: Enum::ValueConverter(Discord::ApplicationCommandType))]
    property type : ApplicationCommandType?
    property resolved : ResolvedInteractionData?
    property options : Array(ApplicationCommandInteractionDataOption)?
    property custom_id : String?
    @[JSON::Field(converter: Enum::ValueConverter(Discord::ComponentType))]
    property component_type : ComponentType?
    property values : Array(String)?
    property target_id : Snowflake?
  end

  struct ResolvedInteractionData
    include JSON::Serializable

    property users : Hash(Snowflake, User)?
    property members : Hash(Snowflake, GuildMember)?
    property roles : Hash(Snowflake, Role)?
    property channels : Hash(Snowflake, Channel)?
  end

  enum InteractionCallbackType : UInt8
    Pong                             = 1
    ChannelMessageWithSource         = 4
    DeferredChannelMessageWithSource = 5
    DeferredUpdateMessage            = 6
    UpdateMessage                    = 7
  end

  struct InteractionResponse
    include JSON::Serializable

    @[JSON::Field(converter: Enum::ValueConverter(Discord::InteractionCallbackType))]
    property type : InteractionCallbackType
    property data : InteractionCallbackData

    def initialize(@type, @data = nil)
    end

    def self.pong
      self.new(InteractionCallbackType::Pong)
    end

    def self.message(data : InteractionCallbackData)
      self.new(InteractionCallbackType::ChannelMessageWithSource, data)
    end

    def self.message(content : String? = nil, embeds : Array(Embed)? = nil,
                     components : Array(ActionRow)? = nil,
                     flags : InteractionCallbackDataFlags? = nil, tts : Bool? = nil)
      data = InteractionCallbackData.new(content, embeds, components, flags, tts)
      self.message(data)
    end

    def self.deferred_message
      self.new(InteractionCallbackType::DeferredChannelMessageWithSource)
    end

    def self.deferred_update_message
      self.new(InteractionCallbackType::DeferredUpdateMessage)
    end

    def self.update_message(data : InteractionCallbackData)
      self.new(InteractionCallbackType::UpdateMessage, data)
    end

    def self.update_message(content : String? = nil, embeds : Array(Embed)? = nil,
                            components : Array(ActionRow)? = nil,
                            flags : InteractionCallbackDataFlags? = nil, tts : Bool? = nil)
      data = InteractionCallbackData.new(content, embeds, components, flags, tts)
      self.update_message(data)
    end
  end

  @[Flags]
  enum InteractionCallbackDataFlags
    Ephemeral = 1 << 6

    def to_json(json : JSON::Builder)
      json.number(value)
    end
  end

  struct InteractionCallbackData
    include JSON::Serializable

    property tts : Bool?
    property content : String?
    property embeds : Array(Embed)?
    # property allowed_mentions : AllowedMentions?
    @[JSON::Field(converter: Enum::ValueConverter(Discord::InteractionCallbackDataFlags))]
    property flags : InteractionCallbackDataFlags?
    property components : Array(ActionRow)?

    def initialize(@content = nil, @embeds = nil, @components = nil, @flags = nil, @tts = nil)
    end
  end
end
