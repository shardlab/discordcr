require "./spec_helper"

describe Discord::Component do
  it "parses ActionRow" do
    btn_json = %({"type":2,"label":"Click me!","style":1,"custom_id":"button_id"})
    json = %({"type":1,"components":[#{btn_json}]})

    obj = Discord::Component.from_json(json)
    btn_obj = Discord::Component.from_json(btn_json)
    obj.should be_a Discord::ActionRow
    obj.as(Discord::ActionRow).components.should eq [btn_obj]
  end

  it "parses Button" do
    json = %({"type":2,"label":"Click me!","style":1,"custom_id":"button_id"})

    obj = Discord::Component.from_json(json)
    obj.should be_a Discord::Button
  end

  it "parses StringSelect" do
    json = %({"type":3,"options":[{"label":"Option 1","value":"1"},{"label":"Option 2","value":"2"}],"custom_id":"select_id"})

    obj = Discord::Component.from_json(json)
    obj.should be_a Discord::SelectMenu
  end

  it "parses TextInput" do
    json = %({"type":4,"label":"Input Label","style":1,"custom_id":"input_id"})

    obj = Discord::Component.from_json(json)
    obj.should be_a Discord::TextInput
  end

  it "parses UserSelect" do
    json = %({"type":5,"custom_id":"select_id"})

    obj = Discord::Component.from_json(json)
    obj.should be_a Discord::SelectMenu
  end

  it "parses RoleSelect" do
    json = %({"type":6,"custom_id":"select_id"})

    obj = Discord::Component.from_json(json)
    obj.should be_a Discord::SelectMenu
  end

  it "parses MentionableSelect" do
    json = %({"type":7,"custom_id":"select_id"})

    obj = Discord::Component.from_json(json)
    obj.should be_a Discord::SelectMenu
  end

  it "parses ChannelSelect" do
    json = %({"type":8,"custom_id":"select_id"})

    obj = Discord::Component.from_json(json)
    obj.should be_a Discord::SelectMenu
  end
end
