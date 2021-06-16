module Discord
  struct Component
    include JSON::Serializable

    @[JSON::Field(converter: Enum::ValueConverter(Discord::ComponentType))]
    property type : ComponentType
    @[JSON::Field(converter: Enum::ValueConverter(Discord::Style))]
    property style : Style?
    property label : String?
    property emoji : Emoji?
    property custom_id : String?
    property url : String?
    property disabled : Bool?
    property components : Array(Component)?

    def initialize(@type, @style = nil, @label = nil, @emoji = nil, @custom_id = nil, @url = nil, @disabled = nil, @components = nil)
    end

    def self.action_row(components = nil)
      self.new(ComponentType::ActionRow, components: components)
    end

    def self.button(style = nil, label = nil, emoji = nil, custom_id = nil, url = nil, disabled = nil)
      self.new(ComponentType::Button, style, label, emoji, custom_id, url, disabled)
    end
  end

  enum ComponentType
    ActionRow = 1
    Button    = 2
  end

  enum Style
    Primary   = 1
    Secondary = 2
    Success   = 3
    Danger    = 4
    Link      = 5
  end
end
