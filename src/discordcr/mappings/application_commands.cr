require "./converters"

module Discord
  enum ApplicationCommandType : UInt8
    ChatInput = 1
    User      = 2
    Message   = 3

    def to_json(json : JSON::Builder)
      json.number(value)
    end
  end

  struct ApplicationCommand
    include JSON::Serializable

    property id : Snowflake
    @[JSON::Field(converter: Enum::ValueConverter(Discord::ApplicationCommandType))]
    property type : ApplicationCommandType?
    property application_id : Snowflake
    property guild_id : Snowflake?
    property name : String
    property description : String
    property options : Array(ApplicationCommandOption)?
    property default_permission : Bool?
    property version : Snowflake
  end

  # `ApplicationCommand` object used for bulk overwriting commands
  struct PartialApplicationCommand
    include JSON::Serializable

    property name : String
    property description : String
    property options : Array(ApplicationCommandOption)?
    property default_permission : Bool?
    @[JSON::Field(converter: Enum::ValueConverter(Discord::ApplicationCommandType))]
    property type : ApplicationCommandType?

    def initialize(@name, @description = "", @options = nil, @default_permission = nil, @type = nil)
    end
  end

  enum ApplicationCommandOptionType : UInt8
    SubCommand      =  1
    SubCommandGroup =  2
    String          =  3
    Integer         =  4
    Boolean         =  5
    User            =  6
    Channel         =  7
    Role            =  8
    Mentionable     =  9
    Number          = 10
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
    property channel_types : Array(ChannelType)?

    def initialize(@type, @name, @description, @required = nil, @choices = nil, @options = nil, @channel_types = nil)
    end

    def self.sub_command(name : String, description : String, required : Bool? = nil,
                         options : Array(ApplicationCommandOption)? = nil)
      self.new(ApplicationCommandOptionType::SubCommand, name, description, required, nil, options, nil)
    end

    def self.sub_command_group(name : String, description : String, required : Bool? = nil,
                               options : Array(ApplicationCommandOption)? = nil)
      self.new(ApplicationCommandOptionType::SubCommandGroup, name, description, required, nil, options, nil)
    end

    def self.string(name : String, description : String, required : Bool? = nil,
                    choices : Array(ApplicationCommandOptionChoice)? = nil)
      self.new(ApplicationCommandOptionType::String, name, description, required, choices, nil, nil)
    end

    def self.integer(name : String, description : String, required : Bool? = nil,
                     choices : Array(ApplicationCommandOptionChoice)? = nil)
      self.new(ApplicationCommandOptionType::Integer, name, description, required, choices, nil, nil)
    end

    def self.boolean(name : String, description : String, required : Bool? = nil)
      self.new(ApplicationCommandOptionType::Boolean, name, description, required, nil, nil, nil)
    end

    def self.user(name : String, description : String, required : Bool? = nil)
      self.new(ApplicationCommandOptionType::User, name, description, required, nil, nil, nil)
    end

    def self.channel(name : String, description : String, required : Bool? = nil, channel_types : Array(ChannelType)? = nil)
      self.new(ApplicationCommandOptionType::Channel, name, description, required, nil, nil, channel_types)
    end

    def self.role(name : String, description : String, required : Bool? = nil)
      self.new(ApplicationCommandOptionType::Role, name, description, required, nil, nil, nil)
    end

    def self.mentionalble(name : String, description : String, required : Bool? = nil)
      self.new(ApplicationCommandOptionType::Mentionable, name, description, required, nil, nil, nil)
    end

    def self.number(name : String, description : String, required : Bool? = nil,
                    choices : Array(ApplicationCommandOptionChoice)? = nil)
      self.new(ApplicationCommandOptionType::Number, name, description, required, choices, nil, nil)
    end
  end

  struct ApplicationCommandOptionChoice
    include JSON::Serializable

    property name : String
    property value : String | Int64 | Float64

    def initialize(@name, @value)
    end
  end

  struct ApplicationCommandInteractionDataOption
    include JSON::Serializable

    def self.new(pull : JSON::PullParser)
      obj = new_from_json_pull_parser(pull)
      
      # The default behavior of serialization prefers String over Snowflake,
      # and if the value is a String but the type tells that it isn't,
      # the value needs to be converted to Snowflake instead
      if (str = obj.value.as?(String)) && !obj.type.string?
        obj.value = Snowflake.new(str)
      end

      obj
    end

    property name : String
    @[JSON::Field(converter: Enum::ValueConverter(Discord::ApplicationCommandOptionType))]
    property type : ApplicationCommandOptionType
    property value : String | Int64 | Float64 | Bool | Snowflake?
    property options : Array(ApplicationCommandInteractionDataOption)?
  end

  struct GuildApplicationCommandPermissions
    include JSON::Serializable

    property id : Snowflake
    property application_id : Snowflake
    property guild_id : Snowflake
    property permissions : Array(ApplicationCommandPermissions)
  end

  enum ApplicationCommandPermissionType : UInt8
    Role = 1
    User = 2
  end

  struct ApplicationCommandPermissions
    include JSON::Serializable

    property id : Snowflake
    @[JSON::Field(converter: Enum::ValueConverter(Discord::ApplicationCommandPermissionType))]
    property type : ApplicationCommandPermissionType
    property permission : Bool

    def initialize(@id, @type, @permission)
    end

    def self.role(id : UInt64 | Snowflake, permissions : Bool)
      id = Snowflake.new(id) unless id.is_a?(Snowflake)
      self.new(id, ApplicationCommandPermissionType::Role, permissions)
    end

    def self.user(id : UInt64 | Snowflake, permissions : Bool)
      id = Snowflake.new(id) unless id.is_a?(Snowflake)
      self.new(id, ApplicationCommandPermissionType::User, permissions)
    end
  end
end
