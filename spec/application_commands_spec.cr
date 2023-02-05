require "./spec_helper"

describe Discord::ApplicationCommandInteractionDataOption do
  it "parses options" do
    opt_json = %({"name":"cat_name","type":3,"value":"tama"})
    json = %({"name":"subcommand","type":1,"options":[#{opt_json}]})

    obj = Discord::ApplicationCommandInteractionDataOption.from_json(json)
    opt_obj = Discord::ApplicationCommandInteractionDataOption.from_json(opt_json)
    obj.options.should eq [opt_obj]
  end

  it "parses value as String" do
    json = %({"name":"animal_type","type":3,"value":"meow"})

    obj = Discord::ApplicationCommandInteractionDataOption.from_json(json)
    obj.value.should be_a String
  end

  it "parses value as Int64" do
    json = %({"name":"animal_type","type":4,"value":1})

    obj = Discord::ApplicationCommandInteractionDataOption.from_json(json)
    obj.value.should be_a Int64
  end

  it "parses value as Bool" do
    json = %({"name":"is_cat","type":5,"value":true})

    obj = Discord::ApplicationCommandInteractionDataOption.from_json(json)
    obj.value.should be_a Bool
  end

  it "parses value as Snowflake" do
    json = %({"name":"user","type":6,"value":"1234567890"})

    obj = Discord::ApplicationCommandInteractionDataOption.from_json(json)
    obj.value.should be_a Discord::Snowflake

    json = %({"name":"channel","type":7,"value":"1234567890"})

    obj = Discord::ApplicationCommandInteractionDataOption.from_json(json)
    obj.value.should be_a Discord::Snowflake

    json = %({"name":"role","type":8,"value":"1234567890"})

    obj = Discord::ApplicationCommandInteractionDataOption.from_json(json)
    obj.value.should be_a Discord::Snowflake

    json = %({"name":"mentionable","type":9,"value":"1234567890"})

    obj = Discord::ApplicationCommandInteractionDataOption.from_json(json)
    obj.value.should be_a Discord::Snowflake
  end

  it "parses value as Float64" do
    json = %({"name":"catfulness","type":10,"value":1.0})

    obj = Discord::ApplicationCommandInteractionDataOption.from_json(json)
    obj.value.should be_a Float64
  end
end
