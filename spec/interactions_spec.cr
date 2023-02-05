require "./spec_helper"

describe Discord::InteractionData do
  it "parses ApplicationCommandInteractionData" do
    json = %({"type":1,"options":[{"value":"woof!","type":3,"name":"animal_type"}],"name":"animal","id":"1071437155282464818"})

    obj = Discord::InteractionData.from_json(json)
    obj.should be_a Discord::ApplicationCommandInteractionData
  end

  it "parses MessageComponentInteractionData" do
    json = %({"custom_id":"add:1","component_type":2})

    obj = Discord::InteractionData.from_json(json)
    obj.should be_a Discord::MessageComponentInteractionData
  end

  it "parses ModalSubmitInteractionData" do
    json = %({"custom_id":"sample_modal","components":[{"type":1,"components":[{"value":"short test","type":4,"custom_id":"short"}]},{"type":1,"components":[{"value":"long test","type":4,"custom_id":"paragraph"}]}]})

    obj = Discord::InteractionData.from_json(json)
    obj.should be_a Discord::ModalSubmitInteractionData
  end
end
