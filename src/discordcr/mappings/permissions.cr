module Discord
  @[Flags]
  enum Permissions : UInt64
    CreateInstantInvite    = 1
    KickMembers            = 1 << 1
    BanMembers             = 1 << 2
    Administrator          = 1 << 3
    ManageChannels         = 1 << 4
    ManageGuild            = 1 << 5
    AddReactions           = 1 << 6
    ViewAuditLog           = 1 << 7
    PrioritySpeaker        = 1 << 8
    Stream                 = 1 << 9
    ReadMessages           = 1 << 10
    SendMessages           = 1 << 11
    SendTTSMessages        = 1 << 12
    ManageMessages         = 1 << 13
    EmbedLinks             = 1 << 14
    AttachFiles            = 1 << 15
    ReadMessageHistory     = 1 << 16
    MentionEveryone        = 1 << 17
    UseExternalEmojis      = 1 << 18
    Connect                = 1 << 20
    Speak                  = 1 << 21
    MuteMembers            = 1 << 22
    DeafenMembers          = 1 << 23
    MoveMembers            = 1 << 24
    UseVAD                 = 1 << 25
    ChangeNickname         = 1 << 26
    ManageNicknames        = 1 << 27
    ManageRoles            = 1 << 28
    ManageWebhooks         = 1 << 29
    ManageEmojis           = 1 << 30
    UseApplicationCommands = 1 << 31
    RequestToSpeak         = 1 << 32
    ManageThreads          = 1 << 34
    UsePrivateThreads      = 1 << 36
    UseExternalStickers    = 1 << 37

    def self.new(pull : JSON::PullParser)
      Permissions.new(pull.read_string.to_u64)
    end

    def to_json(json : JSON::Builder)
      json.string(value)
    end
  end
end
