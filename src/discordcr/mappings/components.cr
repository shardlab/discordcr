require "./converters"

module Discord
  enum ComponentType : UInt8
    ActionRow  = 1
    Button     = 2
    SelectMenu = 3
  end

  enum ButtonStyle : UInt8
    Primary = 1
    Secondary = 2
    Success = 3
    Danger = 4
    Link = 5
  end

  abstract struct Component
    include JSON::Serializable

    use_json_discriminator "type", {
      ComponentType::ActionRow => ActionRow,
      ComponentType::Button => Button,
      ComponentType::SelectMenu => SelectMenu
    }

    @[JSON::Field(converter: Enum::ValueConverter(Discord::ComponentType))]
    property type : ComponentType
  end

  struct ActionRow < Component
    @type : ComponentType = ComponentType::ActionRow

    property components : Array(Button | SelectMenu)

    def initialize(*components : Button | SelectMenu)
      @components = [*components] of Button | SelectMenu
    end
  end

  struct Button < Component
    @type : ComponentType = ComponentType::Button

    @[JSON::Field(converter: Enum::ValueConverter(Discord::ButtonStyle))]
    property style : ButtonStyle
    property label : String?
    property emoji : Emoji?
    property custom_id : String?
    property url : String?
    property disabled : Bool?

    def initialize(@style, @label = nil, @emoji = nil, @custom_id = nil, @url = nil, @disabled = nil)
    end
  end

  struct SelectMenu < Component
    @type : ComponentType = ComponentType::SelectMenu

    property custom_id : String?
    property options : Array(SelectOption)
    property placeholder : String?
    property min_values : UInt8?
    property max_values : UInt8?
    property disabled : Bool?

    def initialize(@options, @custom_id = nil, @placeholder = nil, @min_values = nil, @max_values = nil, @disabled = nil)
    end
  end

  struct SelectOption
    include JSON::Serializable

    property label : String
    property value : String
    property description : String?
    property emoji : Emoji?
    property default : Bool?

    def initialize(@label, @value, @description = nil, @emoji = nil, @default = nil)
    end
  end
end
