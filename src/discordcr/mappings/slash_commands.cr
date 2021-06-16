module Discord
  abstract struct ApplicationCommandAbstract
    include JSON::Serializable
    include AbstractCast

    property id : Snowflake
    property application_id : Snowflake
    property name : String
    property description : String
    property options : Array(ApplicationCommandOption)?
    property default_permission : Bool?
  end

  struct ApplicationCommand < ApplicationCommandAbstract
  end

  # Only used to send bulk overwrite
  struct PartialApplicationCommand
    include JSON::Serializable

    property name : String
    property description : String
    property options : Array(ApplicationCommandOption)?
    property default_permission : Bool?

    def initialize(@name, @description, @options = nil, @default_permission = nil)
    end
  end

  struct ApplicationCommandOption
    include JSON::Serializable

    @[JSON::Field(converter: Enum::ValueConverter(Discord::ApplicationCommandOptionType))]
    property type : ApplicationCommandOptionType
    property name : String
    property description : String
    property required : Bool?
    property choices : Array(ApplicationCommandOptionChoice)?
    property options : Array(ApplicationCommandOption)?

    def initialize(@name, @type, @description, @required = nil, @choices = nil, @options = nil)
    end
  end

  enum ApplicationCommandOptionType
    SubCommand      = 1
    SubCommandGroup = 2
    String          = 3
    Integer         = 4
    Boolean         = 5
    User            = 6
    Channel         = 7
    Role            = 8
    Mentionable     = 9
  end

  struct ApplicationCommandOptionChoice
    include JSON::Serializable

    property name : String
    property value : String | Int32

    def initialize(@name, @value)
    end
  end

  struct GuildApplicationCommandPermissions
    include JSON::Serializable

    property id : Snowflake
    property application_id : Snowflake
    property guild_id : Snowflake
    property permissions : Array(ApplicationCommandPermissions)
  end

  struct ApplicationCommandPermissions
    include JSON::Serializable

    property id : Snowflake
    @[JSON::Field(converter: Enum::ValueConverter(Discord::ApplicationCommandPermissionType))]
    property type : ApplicationCommandPermissionType
    property permission : Bool

    def initialize(@id, @type, @permission)
    end

    def self.role(id : UInt64 | Snowflake, permission)
      id = Snowflake.new(id) if id.is_a?(UInt64)
      self.new(id, ApplicationCommandPermissionType::Role, permission)
    end

    def self.user(id : UInt64 | Snowflake, permission)
      id = Snowflake.new(id) if id.is_a?(UInt64)
      self.new(id, ApplicationCommandPermissionType::User, permission)
    end
  end

  enum ApplicationCommandPermissionType
    Role = 1
    User = 2
  end

  struct Interaction
    include JSON::Serializable

    property id : Snowflake
    property application_id : Snowflake
    @[JSON::Field(converter: Enum::ValueConverter(Discord::InteractionType))]
    property type : InteractionType
    property data : ApplicationCommandInteractionData?
    property guild_id : Snowflake?
    property channel_id : Snowflake?
    property member : GuildMember?
    property user : User?
    property token : String
    property version : UInt32
    property message : Message?
  end

  enum InteractionType
    Ping               = 1
    ApplicationCommand = 2
    MessageComponent   = 3
  end

  struct ApplicationCommandInteractionData
    include JSON::Serializable

    property id : Snowflake?
    property name : String?
    property resolved : ApplicationCommandInteractionDataResolved?
    property options : Array(ApplicationCommandInteractionDataOption)?
    property custom_id : String?
    @[JSON::Field(converter: Enum::ValueConverter(Discord::ComponentType))]
    property component_type : ComponentType?
  end

  struct ApplicationCommandInteractionDataResolved
    include JSON::Serializable

    property users : Hash(Snowflake, User)?
    property members : Hash(Snowflake, GuildMember)?
    property roles : Hash(Snowflake, Role)?
    property channels : Hash(Snowflake, Channel)?
  end

  alias OptionType = String | Int32 | Bool | Snowflake

  struct ApplicationCommandInteractionDataOption
    include JSON::Serializable

    property name : String
    @[JSON::Field(converter: Enum::ValueConverter(Discord::ApplicationCommandOptionType))]
    property type : ApplicationCommandOptionType
    property value : OptionType?
    property options : Array(ApplicationCommandInteractionDataOption)?
  end

  struct InteractionResponse
    include JSON::Serializable

    @[JSON::Field(converter: Enum::ValueConverter(Discord::InteractionCallbackType))]
    property type : InteractionCallbackType
    property data : InteractionApplicationCommandCallbackData?

    def initialize(@type, @data = nil)
    end
  end

  enum InteractionCallbackType
    Pong                             = 1
    ChannelMessageWithSource         = 4
    DeferredChannelMessageWithSource = 5
    DeferredUpdateMessage            = 6
    UpdateMessage                    = 7
  end

  struct InteractionApplicationCommandCallbackData
    include JSON::Serializable

    property tts : Bool?
    property content : String?
    property embeds : Array(Embed)?
    property allowed_mentions : AllowedMentions?
    property flags : UInt32?
    property components : Array(Component)?

    def initialize(@content = nil, @embeds = nil, @components = nil, @flags = nil, @allowed_mentions = nil, @tts = nil)
    end
  end

  struct MessageInteraction
    include JSON::Serializable

    property id : Snowflake
    @[JSON::Field(converter: Enum::ValueConverter(Discord::InteractionType))]
    property type : InteractionType
    property name : String
    property user : User
  end
end
