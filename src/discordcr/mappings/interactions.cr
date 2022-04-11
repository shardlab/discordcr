require "./converters"

module Discord
  enum InteractionType : UInt8
    Ping                           = 1
    ApplicationCommand             = 2
    MessageComponent               = 3
    ApplicationCommandAutocomplete = 4
    ModalSubmit                    = 5
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
    property locale : String?
    property guild_locale : String?
  end

  abstract struct InteractionData
    include JSON::Serializable

    def self.new(pull : JSON::PullParser)
      type = self
      json = String.build do |io|
        JSON.build(io) do |builder|
          builder.start_object
          pull.read_object do |key|
            if key == "id"
              type = ApplicationCommandInteractionData
            elsif key == "custom_id"
              type = MessageComponentInteractionData
            elsif key == "components"
              type = ModalSubmitInteractionData
            end
            builder.field(key) { pull.read_raw(builder) }
          end
          builder.end_object
        end
      end

      type.from_json(json)
    end
  end

  struct ApplicationCommandInteractionData < InteractionData
    property id : Snowflake
    property name : String
    @[JSON::Field(converter: Enum::ValueConverter(Discord::ApplicationCommandType))]
    property type : ApplicationCommandType
    property resolved : ResolvedInteractionData?
    property options : Array(ApplicationCommandInteractionDataOption)?
    property target_id : Snowflake?
  end

  struct MessageComponentInteractionData < InteractionData
    property custom_id : String
    @[JSON::Field(converter: Enum::ValueConverter(Discord::ComponentType))]
    property component_type : ComponentType
    property values : Array(String)?
  end

  struct ModalSubmitInteractionData < InteractionData
    property custom_id : String
    property components : Array(ActionRow)
  end

  struct ResolvedInteractionData
    include JSON::Serializable

    property users : Hash(Snowflake, User)?
    property members : Hash(Snowflake, PartialGuildMember)?
    property roles : Hash(Snowflake, Role)?
    property channels : Hash(Snowflake, Channel)?
    property messages : Hash(Snowflake, Message)?
    property attachments : Hash(Snowflake, Attachment)?
  end

  struct MessageInteraction
    include JSON::Serializable

    property id : Snowflake
    @[JSON::Field(converter: Enum::ValueConverter(Discord::InteractionType))]
    property type : InteractionType
    property name : String
    property user : User
  end

  enum InteractionCallbackType : UInt8
    Pong                                 = 1
    ChannelMessageWithSource             = 4
    DeferredChannelMessageWithSource     = 5
    DeferredUpdateMessage                = 6
    UpdateMessage                        = 7
    ApplicationCommandAutocompleteResult = 8
    Modal                                = 9
  end

  struct InteractionResponse
    include JSON::Serializable

    @[JSON::Field(converter: Enum::ValueConverter(Discord::InteractionCallbackType))]
    property type : InteractionCallbackType
    property data : (InteractionCallbackMessageData | InteractionCallbackAutocompleteData | InteractionCallbackModalData)?

    def initialize(@type, @data = nil)
    end

    def self.pong
      self.new(InteractionCallbackType::Pong)
    end

    def self.message(data : InteractionCallbackMessageData)
      self.new(InteractionCallbackType::ChannelMessageWithSource, data)
    end

    def self.message(content : String? = nil, embeds : Array(Embed)? = nil,
                     components : Array(ActionRow)? = nil,
                     flags : InteractionCallbackDataFlags? = nil, tts : Bool? = nil)
      data = InteractionCallbackMessageData.new(content, embeds, components, flags, tts)
      self.message(data)
    end

    def self.deferred_message(flags : InteractionCallbackDataFlags? = nil)
      data = InteractionCallbackMessageData.new(flags: flags)
      self.new(InteractionCallbackType::DeferredChannelMessageWithSource, data)
    end

    def self.deferred_update_message
      self.new(InteractionCallbackType::DeferredUpdateMessage)
    end

    def self.update_message(data : InteractionCallbackMessageData)
      self.new(InteractionCallbackType::UpdateMessage, data)
    end

    def self.update_message(content : String? = nil, embeds : Array(Embed)? = nil,
                            components : Array(ActionRow)? = nil,
                            flags : InteractionCallbackDataFlags? = nil, tts : Bool? = nil)
      data = InteractionCallbackMessageData.new(content, embeds, components, flags, tts)
      self.update_message(data)
    end

    def self.autocomplete_result(data : InteractionCallbackAutocompleteData)
      self.new(InteractionCallbackType::ApplicationCommandAutocompleteResult, data)
    end

    def self.autocomplete_result(choices : Array(ApplicationCommandOptionChoice))
      data = InteractionCallbackAutocompleteData.new(choices)
      self.new(InteractionCallbackType::ApplicationCommandAutocompleteResult, data)
    end

    def self.modal(data : InteractionCallbackModalData)
      self.new(InteractionCallbackType::Modal, data)
    end

    def self.modal(custom_id : String, title : String, components : Array(ActionRow))
      data = InteractionCallbackModalData.new(custom_id, title, components)
      self.new(InteractionCallbackType::Modal, data)
    end
  end

  @[Flags]
  enum InteractionCallbackDataFlags
    SuppressEmbeds = 1 << 2
    Ephemeral      = 1 << 6

    def to_json(json : JSON::Builder)
      json.number(value)
    end
  end

  struct InteractionCallbackMessageData
    include JSON::Serializable

    property tts : Bool?
    property content : String?
    property embeds : Array(Embed)?
    property allowed_mentions : AllowedMentions?
    @[JSON::Field(converter: Enum::ValueConverter(Discord::InteractionCallbackDataFlags))]
    property flags : InteractionCallbackDataFlags?
    property components : Array(ActionRow)?

    def initialize(@content = nil, @embeds = nil, @components = nil, @flags = nil, @tts = nil)
    end
  end

  struct InteractionCallbackAutocompleteData
    include JSON::Serializable

    property choices : Array(ApplicationCommandOptionChoice)

    def initialize(@choices)
    end
  end

  struct InteractionCallbackModalData
    include JSON::Serializable

    property custom_id : String
    property title : String
    property components : Array(ActionRow)

    def initialize(@custom_id, @title, @components)
    end
  end
end
