require "./channel"

module Discord
  enum ApplicationCommandOptionType : UInt8
    SubCommand      = 1
    SubCommandGroup = 2
    String          = 3
    Integer         = 4
    Boolean         = 5
    User            = 6
    Channel         = 7
    Role            = 8

    def self.new(pull : JSON::PullParser)
      ApplicationCommandOptionType.new(pull.read_int.to_u8)
    end
  end

  struct ApplicationCommand
    include JSON::Serializable

    property id : Snowflake
    property application_id : Snowflake
    property name : String
    property description : String
    property options : Array(ApplicationCommandOption)?
  end

  struct ApplicationCommandOption
    include JSON::Serializable

    property type : ApplicationCommandOptionType
    property name : String
    property description : String
    property default : Bool?
    property required : Bool?
    property choices : Array(ApplicationCommandOptionChoice)?
    property options : Array(ApplicationCommandOption)?
  end

  struct ApplicationCommandOptionChoice
    include JSON::Serializable

    property name : String
    property value : String | UInt32
  end

  enum InteractionType : UInt8
    Ping               = 1
    ApplicationCommand = 2

    def self.new(pull : JSON::PullParser)
      InteractionType.new(pull.read_int.to_u8)
    end
  end

  struct Interaction
    include JSON::Serializable

    property id : Snowflake
    property type : InteractionType
    property data : ApplicationCommandInteractionData?
    property guild_id : Snowflake
    property channel_id : Snowflake
    property member : GuildMember
    property token : String
    property version : UInt8
  end

  struct ApplicationCommandInteractionData
    include JSON::Serializable

    property id : Snowflake
    property name : String
    property options : Array(ApplicationCommandInteractionDataOption)?
  end

  alias OptionType = Snowflake | UInt64 | String | Bool

  struct ApplicationCommandInteractionDataOption
    include JSON::Serializable

    property name : String
    property value : OptionType?
    property options : Array(ApplicationCommandInteractionDataOption)?
  end

  struct InteractionResponse
    include JSON::Serializable

    property type : InteractionResponseType
    property data : InteractionApplicationCommandCallbackData?
  end

  enum InteractionResponseType : UInt8
    Pong                     = 1
    Acknowledge              = 2
    ChannelMessage           = 3
    ChannelMessageWithSource = 4
    ACKWithSource            = 5

    def self.new(pull : JSON::PullParser)
      InteractionResponseType.new(pull.read_int.to_u8)
    end
  end

  struct InteractionApplicationCommandCallbackData
    include JSON::Serializable

    property tts : Bool?
    property content : String
    property embeds : Array(Embed)?
    property allowed_mentions : AllowedMentions?
  end
end
