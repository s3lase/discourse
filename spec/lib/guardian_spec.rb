# frozen_string_literal: true

describe Guardian do

  fab!(:user) { Fabricate(:user) }
  fab!(:another_user) { Fabricate(:user) }
  fab!(:member) { Fabricate(:user) }
  fab!(:owner) { Fabricate(:user) }
  fab!(:moderator) { Fabricate(:moderator) }
  fab!(:admin) { Fabricate(:admin) }
  fab!(:anonymous_user) { Fabricate(:anonymous) }
  fab!(:staff_post) { Fabricate(:post, user: moderator) }
  fab!(:group) { Fabricate(:group) }
  fab!(:another_group) { Fabricate(:group) }
  fab!(:automatic_group) { Fabricate(:group, automatic: true) }
  fab!(:plain_category) { Fabricate(:category) }

  let(:trust_level_0) { build(:user, trust_level: 0) }
  let(:trust_level_1) { build(:user, trust_level: 1) }
  let(:trust_level_2) { build(:user, trust_level: 2) }
  let(:trust_level_3) { build(:user, trust_level: 3) }
  let(:trust_level_4)  { build(:user, trust_level: 4) }
  let(:another_admin) { build(:admin) }
  let(:coding_horror) { build(:coding_horror) }

  let(:topic) { build(:topic, user: user) }
  let(:post) { build(:post, topic: topic, user: topic.user) }

  it 'can be created without a user (not logged in)' do
    expect { Guardian.new }.not_to raise_error
  end

  it 'can be instantiated with a user instance' do
    expect { Guardian.new(user) }.not_to raise_error
  end

  describe "link_posting_access" do
    it "is none for anonymous users" do
      expect(Guardian.new.link_posting_access).to eq('none')
    end

    it "is full for regular users" do
      expect(Guardian.new(user).link_posting_access).to eq('full')
    end

    it "is none for a user of a low trust level" do
      user.trust_level = 0
      SiteSetting.min_trust_to_post_links = 1
      expect(Guardian.new(user).link_posting_access).to eq('none')
    end

    it "is limited for a user of a low trust level with a allowlist" do
      SiteSetting.allowed_link_domains = 'example.com'
      user.trust_level = 0
      SiteSetting.min_trust_to_post_links = 1
      expect(Guardian.new(user).link_posting_access).to eq('limited')
    end
  end

  describe "can_post_link?" do
    let(:host) { "discourse.org" }

    it "returns false for anonymous users" do
      expect(Guardian.new.can_post_link?(host: host)).to eq(false)
    end

    it "returns true for a regular user" do
      expect(Guardian.new(user).can_post_link?(host: host)).to eq(true)
    end

    it "supports customization by site setting" do
      user.trust_level = 0
      SiteSetting.min_trust_to_post_links = 0
      expect(Guardian.new(user).can_post_link?(host: host)).to eq(true)
      SiteSetting.min_trust_to_post_links = 1
      expect(Guardian.new(user).can_post_link?(host: host)).to eq(false)
    end

    describe "allowlisted host" do
      before do
        SiteSetting.allowed_link_domains = host
      end

      it "allows a new user to post the link to the host" do
        user.trust_level = 0
        SiteSetting.min_trust_to_post_links = 1
        expect(Guardian.new(user).can_post_link?(host: host)).to eq(true)
        expect(Guardian.new(user).can_post_link?(host: 'another-host.com')).to eq(false)
      end
    end
  end

  describe '#post_can_act?' do
    let(:post) { build(:post) }
    let(:user) { build(:user) }

    it "returns false when the user is nil" do
      expect(Guardian.new(nil)).not_to be_post_can_act(post, :like)
    end

    it "returns false when the post is nil" do
      expect(Guardian.new(user)).not_to be_post_can_act(nil, :like)
    end

    it "returns false when the topic is archived" do
      post.topic.archived = true
      expect(Guardian.new(user)).not_to be_post_can_act(post, :like)
    end

    it "returns false when the post is deleted" do
      post.deleted_at = Time.now
      expect(Guardian.new(user)).not_to be_post_can_act(post, :like)
      expect(Guardian.new(admin)).to be_post_can_act(post, :spam)
      expect(Guardian.new(admin)).to be_post_can_act(post, :notify_user)
    end

    it "works as expected for silenced users" do
      UserSilencer.silence(user, admin)
      expect(Guardian.new(user)).not_to be_post_can_act(post, :spam)
      expect(Guardian.new(user)).to be_post_can_act(post, :like)
      expect(Guardian.new(user)).to be_post_can_act(post, :bookmark)
    end

    it "allows flagging archived posts" do
      post.topic.archived = true
      expect(Guardian.new(user)).to be_post_can_act(post, :spam)
    end

    it "does not allow flagging of hidden posts" do
      post.hidden = true
      expect(Guardian.new(user)).not_to be_post_can_act(post, :spam)
    end

    it "allows flagging of staff posts when allow_flagging_staff is true" do
      SiteSetting.allow_flagging_staff = true
      expect(Guardian.new(user)).to be_post_can_act(staff_post, :spam)
    end

    describe 'when allow_flagging_staff is false' do
      before do
        SiteSetting.allow_flagging_staff = false
      end

      it "doesn't allow flagging of staff posts" do
        expect(Guardian.new(user).post_can_act?(staff_post, :spam)).to eq(false)
      end

      it "allows flagging of staff posts when staff has been deleted" do
        staff_post.user.destroy!
        staff_post.reload
        expect(Guardian.new(user).post_can_act?(staff_post, :spam)).to eq(true)
      end

      it "allows liking of staff" do
        expect(Guardian.new(user).post_can_act?(staff_post, :like)).to eq(true)
      end
    end

    it "returns false when liking yourself" do
      expect(Guardian.new(post.user)).not_to be_post_can_act(post, :like)
    end

    it "returns false when you've already done it" do
      expect(Guardian.new(user)).not_to be_post_can_act(post, :like, opts: {
        taken_actions: { PostActionType.types[:like] => 1 }
      })
    end

    it "returns false when you already flagged a post" do
      PostActionType.notify_flag_types.each do |type, _id|
        expect(Guardian.new(user)).not_to be_post_can_act(post, :off_topic, opts: {
          taken_actions: { PostActionType.types[type] => 1 }
        })
      end
    end

    it "returns false for notify_user if private messages are disabled" do
      SiteSetting.enable_personal_messages = false
      user.trust_level = TrustLevel[2]
      expect(Guardian.new(user)).not_to be_post_can_act(post, :notify_user)
    end

    it "returns false for notify_user if private messages are enabled but threshold not met" do
      SiteSetting.enable_personal_messages = true
      SiteSetting.min_trust_to_send_messages = 2
      user.trust_level = TrustLevel[1]
      expect(Guardian.new(user)).not_to be_post_can_act(post, :notify_user)
    end

    describe "trust levels" do
      it "returns true for a new user liking something" do
        user.trust_level = TrustLevel[0]
        expect(Guardian.new(user)).to be_post_can_act(post, :like)
      end

      it "returns false for a new user flagging as spam" do
        user.trust_level = TrustLevel[0]
        expect(Guardian.new(user)).not_to be_post_can_act(post, :spam)
      end

      it "returns true for a new user flagging as spam if enabled" do
        SiteSetting.min_trust_to_flag_posts = 0
        user.trust_level = TrustLevel[0]
        expect(Guardian.new(user)).to be_post_can_act(post, :spam)
      end

      it "returns true for a new user flagging a private message as spam" do
        post = Fabricate(:private_message_post, user: admin)
        user.trust_level = TrustLevel[0]
        post.topic.allowed_users << user
        expect(Guardian.new(user)).to be_post_can_act(post, :spam)
      end

      it "returns false for a new user flagging something as off topic" do
        user.trust_level = TrustLevel[0]
        expect(Guardian.new(user)).not_to be_post_can_act(post, :off_topic)
      end

      it "returns false for a new user flagging with notify_user" do
        user.trust_level = TrustLevel[0]
        expect(Guardian.new(user)).not_to be_post_can_act(post, :notify_user) # because new users can't send private messages
      end
    end
  end

  describe "can_enable_safe_mode" do
    let(:user) { Fabricate.build(:user) }
    let(:moderator) { Fabricate.build(:moderator) }

    context "when enabled" do
      before do
        SiteSetting.enable_safe_mode = true
      end

      it "can be performed" do
        expect(Guardian.new.can_enable_safe_mode?).to eq(true)
        expect(Guardian.new(user).can_enable_safe_mode?).to eq(true)
        expect(Guardian.new(moderator).can_enable_safe_mode?).to eq(true)
      end
    end

    context "when disabled" do
      before do
        SiteSetting.enable_safe_mode = false
      end

      it "can be performed" do
        expect(Guardian.new.can_enable_safe_mode?).to eq(false)
        expect(Guardian.new(user).can_enable_safe_mode?).to eq(false)
        expect(Guardian.new(moderator).can_enable_safe_mode?).to eq(true)
      end
    end
  end

  describe 'can_send_private_message' do
    fab!(:suspended_user) { Fabricate(:user, suspended_till: 1.week.from_now, suspended_at: 1.day.ago) }

    it "returns false when the user is nil" do
      expect(Guardian.new(nil)).not_to be_can_send_private_message(user)
    end

    it "returns false when the target user is nil" do
      expect(Guardian.new(user)).not_to be_can_send_private_message(nil)
    end

    it "returns true when the target is the same as the user" do
      # this is now allowed so yay
      expect(Guardian.new(user)).to be_can_send_private_message(user)
    end

    it "returns false when you are untrusted" do
      user.trust_level = TrustLevel[0]
      expect(Guardian.new(user)).not_to be_can_send_private_message(another_user)
    end

    it "returns true to another user" do
      expect(Guardian.new(user)).to be_can_send_private_message(another_user)
    end

    it "disallows pms to other users if trust level is not met" do
      SiteSetting.min_trust_to_send_messages = TrustLevel[2]
      user.trust_level = TrustLevel[1]
      expect(Guardian.new(user)).not_to be_can_send_private_message(another_user)
    end

    context "enable_personal_messages is false" do
      before { SiteSetting.enable_personal_messages = false }

      it "returns false if user is not staff member" do
        expect(Guardian.new(trust_level_4)).not_to be_can_send_private_message(another_user)
      end

      it "returns true for staff member" do
        expect(Guardian.new(moderator)).to be_can_send_private_message(another_user)
        expect(Guardian.new(admin)).to be_can_send_private_message(another_user)
      end
    end

    context "target user is suspended" do
      it "returns true for staff" do
        expect(Guardian.new(admin)).to be_can_send_private_message(suspended_user)
        expect(Guardian.new(moderator)).to be_can_send_private_message(suspended_user)
      end

      it "returns false for regular users" do
        expect(Guardian.new(user)).not_to be_can_send_private_message(suspended_user)
      end
    end

    context "author is silenced" do
      before do
        user.silenced_till = 1.year.from_now
        user.save
      end

      it "returns true if target is staff" do
        expect(Guardian.new(user)).to be_can_send_private_message(admin)
        expect(Guardian.new(user)).to be_can_send_private_message(moderator)
      end

      it "returns false if target is not staff" do
        expect(Guardian.new(user)).not_to be_can_send_private_message(another_user)
      end

      it "returns true if target is a staff group" do
        Group::STAFF_GROUPS.each do |name|
          g = Group[name]
          g.update!(messageable_level: Group::ALIAS_LEVELS[:everyone])
          expect(Guardian.new(user)).to be_can_send_private_message(g)
        end
      end
    end

    it "respects the group's messageable_level" do
      Group::ALIAS_LEVELS.each do |level, _|
        group.update!(messageable_level: Group::ALIAS_LEVELS[level])
        user_output = level == :everyone ? true : false
        admin_output = level != :nobody
        mod_output = [:nobody, :only_admins].exclude?(level)

        expect(Guardian.new(user).can_send_private_message?(group)).to eq(user_output)
        expect(Guardian.new(admin).can_send_private_message?(group)).to eq(admin_output)
        expect(Guardian.new(moderator).can_send_private_message?(group)).to eq(mod_output)
      end
    end

    it "allows TL0 to message group with messageable_level = everyone" do
      group.update!(messageable_level: Group::ALIAS_LEVELS[:everyone])
      expect(Guardian.new(trust_level_0).can_send_private_message?(group)).to eq(true)
      expect(Guardian.new(user).can_send_private_message?(group)).to eq(true)
    end

    it "respects the group members messageable_level" do
      group.update!(messageable_level: Group::ALIAS_LEVELS[:members_mods_and_admins])
      expect(Guardian.new(user).can_send_private_message?(group)).to eq(false)

      group.add(user)
      expect(Guardian.new(user).can_send_private_message?(group)).to eq(true)

      expect(Guardian.new(trust_level_0).can_send_private_message?(group)).to eq(false)

      #  group membership trumps min_trust_to_send_messages setting
      group.add(trust_level_0)
      expect(Guardian.new(trust_level_0).can_send_private_message?(group)).to eq(true)
    end

    it "respects the group owners messageable_level" do
      group.update!(messageable_level: Group::ALIAS_LEVELS[:owners_mods_and_admins])
      expect(Guardian.new(user).can_send_private_message?(group)).to eq(false)

      group.add(user)
      expect(Guardian.new(user).can_send_private_message?(group)).to eq(false)

      group.add_owner(user)
      expect(Guardian.new(user).can_send_private_message?(group)).to eq(true)
    end

    context 'target user has private message disabled' do
      before do
        another_user.user_option.update!(allow_private_messages: false)
      end

      context 'for a normal user' do
        it 'should return false' do
          expect(Guardian.new(user).can_send_private_message?(another_user)).to eq(false)
        end
      end

      context 'for a staff user' do
        it 'should return true' do
          [admin, moderator].each do |staff_user|
            expect(Guardian.new(staff_user).can_send_private_message?(another_user))
              .to eq(true)
          end
        end
      end
    end
  end

  describe 'can_reply_as_new_topic' do
    fab!(:topic) { Fabricate(:topic) }
    fab!(:private_message) { Fabricate(:private_message_topic) }

    it "returns false for a non logged in user" do
      expect(Guardian.new(nil)).not_to be_can_reply_as_new_topic(topic)
    end

    it "returns false for a nil topic" do
      expect(Guardian.new(user)).not_to be_can_reply_as_new_topic(nil)
    end

    it "returns false for an untrusted user" do
      user.trust_level = TrustLevel[0]
      expect(Guardian.new(user)).not_to be_can_reply_as_new_topic(topic)
    end

    it "returns true for a trusted user" do
      expect(Guardian.new(user)).to be_can_reply_as_new_topic(topic)
    end

    it "returns true for a private message" do
      expect(Guardian.new(user)).to be_can_reply_as_new_topic(private_message)
    end
  end

  describe 'can_see_post_actors?' do

    let(:topic) { Fabricate(:topic, user: coding_horror) }

    it 'displays visibility correctly' do
      guardian = Guardian.new(user)
      expect(guardian).not_to be_can_see_post_actors(nil, PostActionType.types[:like])
      expect(guardian).to be_can_see_post_actors(topic, PostActionType.types[:like])
      expect(guardian).not_to be_can_see_post_actors(topic, PostActionType.types[:off_topic])
      expect(guardian).not_to be_can_see_post_actors(topic, PostActionType.types[:spam])
      expect(guardian).not_to be_can_see_post_actors(topic, PostActionType.types[:notify_user])

      expect(Guardian.new(moderator)).to be_can_see_post_actors(topic, PostActionType.types[:notify_user])
    end

  end

  describe 'can_impersonate?' do
    it 'allows impersonation correctly' do
      expect(Guardian.new(admin)).not_to be_can_impersonate(nil)
      expect(Guardian.new).not_to be_can_impersonate(user)
      expect(Guardian.new(coding_horror)).not_to be_can_impersonate(user)
      expect(Guardian.new(admin)).not_to be_can_impersonate(admin)
      expect(Guardian.new(admin)).not_to be_can_impersonate(another_admin)
      expect(Guardian.new(admin)).to be_can_impersonate(user)
      expect(Guardian.new(admin)).to be_can_impersonate(moderator)

      Rails.configuration.stubs(:developer_emails).returns([admin.email])
      expect(Guardian.new(admin)).to be_can_impersonate(another_admin)
    end
  end

  describe "can_view_action_logs?" do
    it 'is false for non-staff acting user' do
      expect(Guardian.new(user)).not_to be_can_view_action_logs(moderator)
    end

    it 'is false without a target user' do
      expect(Guardian.new(moderator)).not_to be_can_view_action_logs(nil)
    end

    it 'is true when target user is present' do
      expect(Guardian.new(moderator)).to be_can_view_action_logs(user)
    end
  end

  describe 'can_invite_to_forum?' do
    let(:user) { Fabricate.build(:user) }
    let(:moderator) { Fabricate.build(:moderator) }

    it 'returns true if user has sufficient trust level' do
      SiteSetting.min_trust_level_to_allow_invite = 2
      expect(Guardian.new(trust_level_2)).to be_can_invite_to_forum
      expect(Guardian.new(moderator)).to be_can_invite_to_forum
    end

    it 'returns false if user trust level does not have sufficient trust level' do
      SiteSetting.min_trust_level_to_allow_invite = 2
      expect(Guardian.new(trust_level_1)).not_to be_can_invite_to_forum
    end

    it "doesn't allow anonymous users to invite" do
      expect(Guardian.new).not_to be_can_invite_to_forum
    end

    it 'returns true when the site requires approving users' do
      SiteSetting.must_approve_users = true
      expect(Guardian.new(trust_level_2)).to be_can_invite_to_forum
    end

    it 'returns false when max_invites_per_day is 0' do
      # let's also break it while here
      SiteSetting.max_invites_per_day = "a"

      expect(Guardian.new(user)).not_to be_can_invite_to_forum
      # staff should be immune to max_invites_per_day setting
      expect(Guardian.new(moderator)).to be_can_invite_to_forum
    end

    context 'with groups' do
      let(:groups) { [group, another_group] }

      before do
        user.update!(trust_level: TrustLevel[2])
        group.add_owner(user)
      end

      it 'returns false when user is not allowed to edit a group' do
        expect(Guardian.new(user).can_invite_to_forum?(groups)).to eq(false)

        expect(Guardian.new(admin).can_invite_to_forum?(groups))
          .to eq(true)
      end

      it 'returns true when user is allowed to edit groups' do
        another_group.add_owner(user)

        expect(Guardian.new(user).can_invite_to_forum?(groups)).to eq(true)
      end
    end
  end

  describe 'can_invite_to?' do

    describe "regular topics" do
      before do
        SiteSetting.min_trust_level_to_allow_invite = 2
        user.update!(trust_level: SiteSetting.min_trust_level_to_allow_invite)
      end
      fab!(:category) { Fabricate(:category, read_restricted: true) }
      fab!(:topic) { Fabricate(:topic) }
      fab!(:private_topic) { Fabricate(:topic, category: category) }
      fab!(:user) { topic.user }
      let(:private_category)  { Fabricate(:private_category, group: group) }
      let(:group_private_topic) { Fabricate(:topic, category: private_category) }
      let(:group_owner) { group_private_topic.user.tap { |u| group.add_owner(u) } }

      it 'handles invitation correctly' do
        expect(Guardian.new(nil)).not_to be_can_invite_to(topic)
        expect(Guardian.new(moderator)).not_to be_can_invite_to(nil)
        expect(Guardian.new(moderator)).to be_can_invite_to(topic)
        expect(Guardian.new(trust_level_1)).to be_can_invite_to(topic)

        SiteSetting.max_invites_per_day = 0

        expect(Guardian.new(user)).to be_can_invite_to(topic)
        # staff should be immune to max_invites_per_day setting
        expect(Guardian.new(moderator)).to be_can_invite_to(topic)
      end

      it 'returns false for normal user on private topic' do
        expect(Guardian.new(user)).not_to be_can_invite_to(private_topic)
      end

      it 'returns false for admin on private topic' do
        expect(Guardian.new(admin).can_invite_to?(private_topic)).to be(false)
      end

      it 'returns true for a group owner' do
        group_owner.update!(trust_level: SiteSetting.min_trust_level_to_allow_invite)
        expect(Guardian.new(group_owner)).to be_can_invite_to(group_private_topic)
      end

      it 'returns true for normal user when inviting to topic and PM disabled' do
        SiteSetting.enable_personal_messages = false
        expect(Guardian.new(trust_level_2)).to be_can_invite_to(topic)
      end

      it 'return true for normal users even if must_approve_users' do
        SiteSetting.must_approve_users = true
        expect(Guardian.new(user)).to be_can_invite_to(topic)
        expect(Guardian.new(admin)).to be_can_invite_to(topic)
      end

      describe 'for a private category for automatic and non-automatic group' do
        let(:category) do
          Fabricate(:category, read_restricted: true).tap do |category|
            category.groups << automatic_group
            category.groups << group
          end
        end

        let(:topic) { Fabricate(:topic, category: category) }

        it 'should return true for an admin user' do
          expect(Guardian.new(admin).can_invite_to?(topic)).to eq(true)
        end

        it 'should return true for a group owner' do
          group_owner.update!(trust_level: SiteSetting.min_trust_level_to_allow_invite)
          expect(Guardian.new(group_owner).can_invite_to?(topic)).to eq(true)
        end

        it 'should return false for a normal user' do
          expect(Guardian.new(user).can_invite_to?(topic)).to eq(false)
        end
      end

      describe 'for a private category for automatic groups' do
        let(:category) do
          Fabricate(:private_category, group: automatic_group, read_restricted: true)
        end

        let(:group_owner) { Fabricate(:user).tap { |user| automatic_group.add_owner(user) } }
        let(:topic) { Fabricate(:topic, category: category) }

        it 'should return false for all type of users' do
          expect(Guardian.new(admin).can_invite_to?(topic)).to eq(false)
          expect(Guardian.new(group_owner).can_invite_to?(topic)).to eq(false)
          expect(Guardian.new(user).can_invite_to?(topic)).to eq(false)
        end
      end
    end

    describe "private messages" do
      fab!(:user) { Fabricate(:user, trust_level: TrustLevel[2]) }
      fab!(:user) { Fabricate(:user, trust_level: SiteSetting.min_trust_level_to_allow_invite) }
      fab!(:pm) { Fabricate(:private_message_topic, user: user) }

      context "when private messages are disabled" do
        it "allows an admin to invite to the pm" do
          expect(Guardian.new(admin)).to be_can_invite_to(pm)
          expect(Guardian.new(user)).to be_can_invite_to(pm)
        end
      end

      context "when private messages are disabled" do
        before do
          SiteSetting.enable_personal_messages = false
        end

        it "doesn't allow a regular user to invite" do
          expect(Guardian.new(admin)).to be_can_invite_to(pm)
          expect(Guardian.new(user)).not_to be_can_invite_to(pm)
        end
      end

      context "when PM has reached the maximum number of recipients" do
        before do
          SiteSetting.max_allowed_message_recipients = 2
        end

        it "doesn't allow a regular user to invite" do
          expect(Guardian.new(user)).not_to be_can_invite_to(pm)
        end

        it "allows staff to invite" do
          expect(Guardian.new(admin)).to be_can_invite_to(pm)
          pm.grant_permission_to_user(moderator.email)
          expect(Guardian.new(moderator)).to be_can_invite_to(pm)
        end
      end
    end
  end

  describe 'can_invite_via_email?' do
    it 'returns true for all (tl2 and above) users when sso is disabled, local logins are enabled, user approval is not required' do
      expect(Guardian.new(trust_level_2)).to be_can_invite_via_email(topic)
      expect(Guardian.new(moderator)).to be_can_invite_via_email(topic)
      expect(Guardian.new(admin)).to be_can_invite_via_email(topic)
    end

    it 'returns true for all users when sso is enabled' do
      SiteSetting.discourse_connect_url = "https://www.example.com/sso"
      SiteSetting.enable_discourse_connect = true

      expect(Guardian.new(trust_level_2)).to be_can_invite_via_email(topic)
      expect(Guardian.new(moderator)).to be_can_invite_via_email(topic)
      expect(Guardian.new(admin)).to be_can_invite_via_email(topic)
    end

    it 'returns false for all users when local logins are disabled' do
      SiteSetting.enable_local_logins = false

      expect(Guardian.new(trust_level_2)).not_to be_can_invite_via_email(topic)
      expect(Guardian.new(moderator)).not_to be_can_invite_via_email(topic)
      expect(Guardian.new(admin)).not_to be_can_invite_via_email(topic)
    end

    it 'returns correct values when user approval is required' do
      SiteSetting.must_approve_users = true

      expect(Guardian.new(trust_level_2)).not_to be_can_invite_via_email(topic)
      expect(Guardian.new(moderator)).to be_can_invite_via_email(topic)
      expect(Guardian.new(admin)).to be_can_invite_via_email(topic)
    end
  end

  describe 'can_see?' do

    it 'returns false with a nil object' do
      expect(Guardian.new).not_to be_can_see(nil)
    end

    describe 'a Category' do

      it 'allows public categories' do
        public_category = build(:category, read_restricted: false)
        expect(Guardian.new).to be_can_see(public_category)
      end

      it 'correctly handles secure categories' do
        normal_user = build(:user)
        staged_user = build(:user, staged: true)
        admin_user  = build(:user, admin: true)

        secure_category = build(:category, read_restricted: true)
        expect(Guardian.new(normal_user)).not_to be_can_see(secure_category)
        expect(Guardian.new(staged_user)).not_to be_can_see(secure_category)
        expect(Guardian.new(admin_user)).to be_can_see(secure_category)

        secure_category = build(:category, read_restricted: true, email_in: "foo@bar.com")
        expect(Guardian.new(normal_user)).not_to be_can_see(secure_category)
        expect(Guardian.new(staged_user)).not_to be_can_see(secure_category)
        expect(Guardian.new(admin_user)).to be_can_see(secure_category)

        secure_category = build(:category, read_restricted: true, email_in_allow_strangers: true)
        expect(Guardian.new(normal_user)).not_to be_can_see(secure_category)
        expect(Guardian.new(staged_user)).not_to be_can_see(secure_category)
        expect(Guardian.new(admin_user)).to be_can_see(secure_category)

        secure_category = build(:category, read_restricted: true, email_in: "foo@bar.com", email_in_allow_strangers: true)
        expect(Guardian.new(normal_user)).not_to be_can_see(secure_category)
        expect(Guardian.new(staged_user)).to be_can_see(secure_category)
        expect(Guardian.new(admin_user)).to be_can_see(secure_category)
      end

      it 'allows members of an authorized group' do
        secure_category = plain_category
        secure_category.set_permissions(group => :readonly)
        secure_category.save

        expect(Guardian.new(user)).not_to be_can_see(secure_category)

        group.add(user)
        group.save

        expect(Guardian.new(user)).to be_can_see(secure_category)
      end

    end

    describe 'a Topic' do
      it 'allows non logged in users to view topics' do
        expect(Guardian.new).to be_can_see(topic)
      end

      it 'correctly handles groups' do
        category = Fabricate(:category, read_restricted: true)
        category.set_permissions(group => :full)
        category.save

        topic = Fabricate(:topic, category: category)

        expect(Guardian.new(user)).not_to be_can_see(topic)
        group.add(user)
        group.save

        expect(Guardian.new(user)).to be_can_see(topic)
      end

      it "restricts deleted topics" do
        topic = Fabricate(:topic)
        topic.trash!(moderator)

        expect(Guardian.new(build(:user))).not_to be_can_see(topic)
        expect(Guardian.new(moderator)).to be_can_see(topic)
        expect(Guardian.new(admin)).to be_can_see(topic)
      end

      it "restricts private topics" do
        user.save!
        private_topic = Fabricate(:private_message_topic, user: user)
        expect(Guardian.new(private_topic.user)).to be_can_see(private_topic)
        expect(Guardian.new(build(:user))).not_to be_can_see(private_topic)
        expect(Guardian.new(moderator)).not_to be_can_see(private_topic)
        expect(Guardian.new(admin)).to be_can_see(private_topic)
      end

      it "restricts private deleted topics" do
        user.save!
        private_topic = Fabricate(:private_message_topic, user: user)
        private_topic.trash!(admin)

        expect(Guardian.new(private_topic.user)).not_to be_can_see(private_topic)
        expect(Guardian.new(build(:user))).not_to be_can_see(private_topic)
        expect(Guardian.new(moderator)).not_to be_can_see(private_topic)
        expect(Guardian.new(admin)).to be_can_see(private_topic)
      end

      it "restricts static doc topics" do
        tos_topic = Fabricate(:topic, user: Discourse.system_user)
        SiteSetting.tos_topic_id = tos_topic.id

        expect(Guardian.new(build(:user))).not_to be_can_edit(tos_topic)
        expect(Guardian.new(moderator)).not_to be_can_edit(tos_topic)
        expect(Guardian.new(admin)).to be_can_edit(tos_topic)
      end

      it "allows moderators to see a flagged private message" do
        moderator.save!
        user.save!

        private_topic = Fabricate(:private_message_topic, user: user)
        first_post = Fabricate(:post, topic: private_topic, user: user)

        expect(Guardian.new(moderator)).not_to be_can_see(private_topic)

        PostActionCreator.create(user, first_post, :off_topic)
        expect(Guardian.new(moderator)).to be_can_see(private_topic)
      end

      it "allows staff to set banner topics" do
        topic = Fabricate(:topic)

        expect(Guardian.new(admin)).not_to be_can_banner_topic(nil)
        expect(Guardian.new(admin)).to be_can_banner_topic(topic)
      end

      it 'respects category group moderator settings' do
        group_user = Fabricate(:group_user)
        user_gm = group_user.user
        group = group_user.group
        SiteSetting.enable_category_group_moderation = true

        topic = Fabricate(:topic)

        expect(Guardian.new(user_gm)).to be_can_see(topic)

        topic.trash!(admin)
        topic.reload

        expect(Guardian.new(user_gm)).not_to be_can_see(topic)

        topic.category.update!(reviewable_by_group_id: group.id, topic_id: post.topic.id)
        expect(Guardian.new(user_gm)).to be_can_see(topic)
      end
    end

    describe 'a Post' do
      fab!(:post) { Fabricate(:post) }
      fab!(:another_admin) { Fabricate(:admin) }

      it 'correctly handles post visibility' do
        topic = post.topic

        expect(Guardian.new(user)).to be_can_see(post)

        post.trash!(another_admin)
        post.reload
        expect(Guardian.new(user)).not_to be_can_see(post)
        expect(Guardian.new(admin)).to be_can_see(post)

        post.recover!
        post.reload
        topic.trash!(another_admin)
        topic.reload
        expect(Guardian.new(user)).not_to be_can_see(post)
        expect(Guardian.new(admin)).to be_can_see(post)
      end

      it 'respects category group moderator settings' do
        group_user = Fabricate(:group_user)
        user_gm = group_user.user
        group = group_user.group
        SiteSetting.enable_category_group_moderation = true

        expect(Guardian.new(user_gm)).to be_can_see(post)

        post.trash!(another_admin)
        post.reload

        expect(Guardian.new(user_gm)).not_to be_can_see(post)

        post.topic.category.update!(reviewable_by_group_id: group.id, topic_id: post.topic.id)
        expect(Guardian.new(user_gm)).to be_can_see(post)
      end

      it 'TL4 users can see their deleted posts' do
        user = Fabricate(:user, trust_level: 4)
        user2 = Fabricate(:user, trust_level: 4)
        post = Fabricate(:post, user: user, topic: Fabricate(:post).topic)

        expect(Guardian.new(user).can_see?(post)).to eq(true)
        PostDestroyer.new(user, post).destroy
        expect(Guardian.new(user).can_see?(post)).to eq(true)
        expect(Guardian.new(user2).can_see?(post)).to eq(false)
      end

      it 'respects whispers' do
        SiteSetting.enable_whispers = true
        SiteSetting.whispers_allowed_groups = "#{group.id}"
        regular_post = post
        whisper_post = Fabricate.build(:post, post_type: Post.types[:whisper])

        anon_guardian = Guardian.new
        expect(anon_guardian.can_see?(regular_post)).to eq(true)
        expect(anon_guardian.can_see?(whisper_post)).to eq(false)

        regular_user = Fabricate.build(:user)
        regular_guardian = Guardian.new(regular_user)
        expect(regular_guardian.can_see?(regular_post)).to eq(true)
        expect(regular_guardian.can_see?(whisper_post)).to eq(false)

        # can see your own whispers
        regular_whisper = Fabricate.build(:post, post_type: Post.types[:whisper], user: regular_user)
        expect(regular_guardian.can_see?(regular_whisper)).to eq(true)

        mod_guardian = Guardian.new(Fabricate.build(:moderator))
        expect(mod_guardian.can_see?(regular_post)).to eq(true)
        expect(mod_guardian.can_see?(whisper_post)).to eq(true)

        admin_guardian = Guardian.new(Fabricate.build(:admin))
        expect(admin_guardian.can_see?(regular_post)).to eq(true)
        expect(admin_guardian.can_see?(whisper_post)).to eq(true)

        whisperer_guardian = Guardian.new(Fabricate(:user, groups: [group]))
        expect(whisperer_guardian.can_see?(regular_post)).to eq(true)
        expect(whisperer_guardian.can_see?(whisper_post)).to eq(true)
      end
    end

    describe 'a PostRevision' do
      fab!(:post_revision) { Fabricate(:post_revision) }

      context 'edit_history_visible_to_public is true' do
        before { SiteSetting.edit_history_visible_to_public = true }

        it 'is false for nil' do
          expect(Guardian.new).not_to be_can_see(nil)
        end

        it 'is true if not logged in' do
          expect(Guardian.new).to be_can_see(post_revision)
        end

        it 'is true when logged in' do
          expect(Guardian.new(user)).to be_can_see(post_revision)
        end
      end

      context 'edit_history_visible_to_public is false' do
        before { SiteSetting.edit_history_visible_to_public = false }

        it 'is true for staff' do
          expect(Guardian.new(admin)).to be_can_see(post_revision)
          expect(Guardian.new(moderator)).to be_can_see(post_revision)
        end

        it 'is false for trust level equal or lower than 4' do
          expect(Guardian.new(trust_level_3)).not_to be_can_see(post_revision)
          expect(Guardian.new(trust_level_4)).not_to be_can_see(post_revision)
        end
      end
    end
  end

  describe 'can_create?' do

    describe 'a Category' do

      it 'returns false when not logged in' do
        expect(Guardian.new).not_to be_can_create(Category)
      end

      it 'returns false when a regular user' do
        expect(Guardian.new(user)).not_to be_can_create(Category)
      end

      it 'returns false when a moderator' do
        expect(Guardian.new(moderator)).not_to be_can_create(Category)
      end

      it 'returns true when an admin' do
        expect(Guardian.new(admin)).to be_can_create(Category)
      end
    end

    describe 'a Topic' do
      it 'does not allow moderators to create topics in readonly categories' do
        category = plain_category
        category.set_permissions(everyone: :read)
        category.save

        expect(Guardian.new(moderator)).not_to be_can_create(Topic, category)
      end

      it 'should check for full permissions' do
        category = plain_category
        category.set_permissions(everyone: :create_post)
        category.save
        expect(Guardian.new(user)).not_to be_can_create(Topic, category)
      end

      it "is true for new users by default" do
        expect(Guardian.new(user)).to be_can_create(Topic, plain_category)
      end

      it "is false if user has not met minimum trust level" do
        SiteSetting.min_trust_to_create_topic = 1
        expect(Guardian.new(build(:user, trust_level: 0))).not_to be_can_create(Topic, plain_category)
      end

      it "is true if user has met or exceeded the minimum trust level" do
        SiteSetting.min_trust_to_create_topic = 1
        expect(Guardian.new(build(:user, trust_level: 1))).to be_can_create(Topic, plain_category)
        expect(Guardian.new(build(:user, trust_level: 2))).to be_can_create(Topic, plain_category)
        expect(Guardian.new(build(:admin, trust_level: 0))).to be_can_create(Topic, plain_category)
        expect(Guardian.new(build(:moderator, trust_level: 0))).to be_can_create(Topic, plain_category)
      end
    end

    describe 'a Post' do

      it "is false on readonly categories" do
        category = plain_category
        topic.category = category
        category.set_permissions(everyone: :readonly)
        category.save

        expect(Guardian.new(topic.user)).not_to be_can_create(Post, topic)
        expect(Guardian.new(moderator)).not_to be_can_create(Post, topic)
      end

      it "is false when not logged in" do
        expect(Guardian.new).not_to be_can_create(Post, topic)
      end

      it 'is true for a regular user' do
        expect(Guardian.new(topic.user)).to be_can_create(Post, topic)
      end

      it "is false when you can't see the topic" do
        Guardian.any_instance.expects(:can_see?).with(topic).returns(false)
        expect(Guardian.new(topic.user)).not_to be_can_create(Post, topic)
      end

      context 'closed topic' do
        before do
          topic.closed = true
        end

        it "doesn't allow new posts from regular users" do
          expect(Guardian.new(topic.user)).not_to be_can_create(Post, topic)
        end

        it 'allows editing of posts' do
          expect(Guardian.new(topic.user)).to be_can_edit(post)
        end

        it "allows new posts from moderators" do
          expect(Guardian.new(moderator)).to be_can_create(Post, topic)
        end

        it "allows new posts from admins" do
          expect(Guardian.new(admin)).to be_can_create(Post, topic)
        end

        it "allows new posts from trust_level_4s" do
          expect(Guardian.new(trust_level_4)).to be_can_create(Post, topic)
        end
      end

      context 'archived topic' do
        before do
          topic.archived = true
        end

        context 'regular users' do
          it "doesn't allow new posts from regular users" do
            expect(Guardian.new(coding_horror)).not_to be_can_create(Post, topic)
          end

          it 'does not allow editing of posts' do
            expect(Guardian.new(coding_horror)).not_to be_can_edit(post)
          end
        end

        it "allows new posts from moderators" do
          expect(Guardian.new(moderator)).to be_can_create(Post, topic)
        end

        it "allows new posts from admins" do
          expect(Guardian.new(admin)).to be_can_create(Post, topic)
        end
      end

      context "trashed topic" do
        before do
          topic.deleted_at = Time.now
        end

        it "doesn't allow new posts from regular users" do
          expect(Guardian.new(coding_horror)).not_to be_can_create(Post, topic)
        end

        it "doesn't allow new posts from moderators users" do
          expect(Guardian.new(moderator)).not_to be_can_create(Post, topic)
        end

        it "doesn't allow new posts from admins" do
          expect(Guardian.new(admin)).not_to be_can_create(Post, topic)
        end
      end

      context "system message" do
        fab!(:private_message) {
          Fabricate(
            :topic,
            archetype: Archetype.private_message,
            subtype: 'system_message',
            category_id: nil
          )
        }

        before { user.save! }
        it "allows the user to reply to system messages" do
          expect(Guardian.new(user).can_create_post?(private_message)).to eq(true)
          SiteSetting.enable_system_message_replies = false
          expect(Guardian.new(user).can_create_post?(private_message)).to eq(false)
        end

      end

      context "private message" do
        fab!(:private_message) { Fabricate(:topic, archetype: Archetype.private_message, category_id: nil) }

        before { user.save! }

        it "allows new posts by people included in the pm" do
          private_message.topic_allowed_users.create!(user_id: user.id)
          expect(Guardian.new(user)).to be_can_create(Post, private_message)
        end

        it "doesn't allow new posts by people not invited to the pm" do
          expect(Guardian.new(user)).not_to be_can_create(Post, private_message)
        end

        it "allows new posts from silenced users included in the pm" do
          user.update_attribute(:silenced_till, 1.year.from_now)
          private_message.topic_allowed_users.create!(user_id: user.id)
          expect(Guardian.new(user)).to be_can_create(Post, private_message)
        end

        it "doesn't allow new posts from silenced users not invited to the pm" do
          user.update_attribute(:silenced_till, 1.year.from_now)
          expect(Guardian.new(user)).not_to be_can_create(Post, private_message)
        end
      end
    end # can_create? a Post

  end

  describe 'post_can_act?' do

    it "isn't allowed on nil" do
      expect(Guardian.new(user)).not_to be_post_can_act(nil, nil)
    end

    describe 'a Post' do

      let (:guardian) do
        Guardian.new(user)
      end

      it "isn't allowed when not logged in" do
        expect(Guardian.new(nil)).not_to be_post_can_act(post, :vote)
      end

      it "is allowed as a regular user" do
        expect(guardian).to be_post_can_act(post, :vote)
      end

      it "isn't allowed on archived topics" do
        topic.archived = true
        expect(Guardian.new(user)).not_to be_post_can_act(post, :like)
      end
    end
  end

  describe "can_recover_topic?" do
    fab!(:topic) { Fabricate(:topic, user: user) }
    fab!(:post) { Fabricate(:post, user: user, topic: topic) }

    it "returns false for a nil user" do
      expect(Guardian.new(nil)).not_to be_can_recover_topic(topic)
    end

    it "returns false for a nil object" do
      expect(Guardian.new(user)).not_to be_can_recover_topic(nil)
    end

    it "returns false for a regular user" do
      expect(Guardian.new(user)).not_to be_can_recover_topic(topic)
    end

    context 'as a moderator' do
      describe 'when post has been deleted' do
        it "should return the right value" do
          expect(Guardian.new(moderator)).not_to be_can_recover_topic(topic)

          PostDestroyer.new(moderator, topic.first_post).destroy

          expect(Guardian.new(moderator)).to be_can_recover_topic(topic.reload)
        end
      end

      describe "when post's user has been deleted" do
        it 'should return the right value' do
          PostDestroyer.new(moderator, topic.first_post).destroy
          topic.first_post.user.destroy!

          expect(Guardian.new(moderator)).to be_can_recover_topic(topic.reload)
        end
      end
    end

    context 'category group moderation is enabled' do
      fab!(:group_user) { Fabricate(:group_user) }

      before do
        SiteSetting.enable_category_group_moderation = true
        PostDestroyer.new(moderator, topic.first_post).destroy
        topic.reload
      end

      it "returns false if user is not a member of the appropriate group" do
        expect(Guardian.new(group_user.user)).not_to be_can_recover_topic(topic)
      end

      it "returns true if user is a member of the appropriate group" do
        topic.category.update!(reviewable_by_group_id: group_user.group.id)

        expect(Guardian.new(group_user.user)).to be_can_recover_topic(topic)
      end
    end
  end

  describe "can_recover_post?" do

    it "returns false for a nil user" do
      expect(Guardian.new(nil)).not_to be_can_recover_post(post)
    end

    it "returns false for a nil object" do
      expect(Guardian.new(user)).not_to be_can_recover_post(nil)
    end

    it "returns false for a regular user" do
      expect(Guardian.new(user)).not_to be_can_recover_post(post)
    end

    context 'as a moderator' do
      fab!(:topic) { Fabricate(:topic, user: user) }
      fab!(:post) { Fabricate(:post, user: user, topic: topic) }

      describe 'when post has been deleted' do
        it "should return the right value" do
          expect(Guardian.new(moderator)).not_to be_can_recover_post(post)

          PostDestroyer.new(moderator, post).destroy

          expect(Guardian.new(moderator)).to be_can_recover_post(post.reload)
        end

        describe "when post's user has been deleted" do
          it 'should return the right value' do
            PostDestroyer.new(moderator, post).destroy
            post.user.destroy!

            expect(Guardian.new(moderator)).to be_can_recover_post(post.reload)
          end
        end
      end
    end

  end

  context 'can_convert_topic?' do
    it 'returns false with a nil object' do
      expect(Guardian.new(user)).not_to be_can_convert_topic(nil)
    end

    it 'returns false when not logged in' do
      expect(Guardian.new).not_to be_can_convert_topic(topic)
    end

    it 'returns false when not staff' do
      expect(Guardian.new(trust_level_4)).not_to be_can_convert_topic(topic)
    end

    it 'returns false for category definition topics' do
      c = plain_category
      topic = Topic.find_by(id: c.topic_id)
      expect(Guardian.new(admin)).not_to be_can_convert_topic(topic)
    end

    it 'returns true when a moderator' do
      expect(Guardian.new(moderator)).to be_can_convert_topic(topic)
    end

    it 'returns true when an admin' do
      expect(Guardian.new(admin)).to be_can_convert_topic(topic)
    end

    it 'returns false when personal messages are disabled' do
      SiteSetting.enable_personal_messages = false
      expect(Guardian.new(admin)).not_to be_can_convert_topic(topic)
    end
  end

  describe 'can_edit?' do

    it 'returns false with a nil object' do
      expect(Guardian.new(user)).not_to be_can_edit(nil)
    end

    describe 'a Post' do

      it 'returns false for silenced users' do
        post.user.silenced_till = 1.day.from_now
        expect(Guardian.new(post.user)).not_to be_can_edit(post)
      end

      it 'returns false when not logged in' do
        expect(Guardian.new).not_to be_can_edit(post)
      end

      it 'returns false when not logged in also for wiki post' do
        post.wiki = true
        expect(Guardian.new).not_to be_can_edit(post)
      end

      it 'returns true if you want to edit your own post' do
        expect(Guardian.new(post.user)).to be_can_edit(post)
      end

      it 'returns false if you try to edit a locked post' do
        post.locked_by_id = moderator.id
        expect(Guardian.new(post.user)).not_to be_can_edit(post)
      end

      it "returns false if the post is hidden due to flagging and it's too soon" do
        post.hidden = true
        post.hidden_at = Time.now
        expect(Guardian.new(post.user)).not_to be_can_edit(post)
      end

      it "returns true if the post is hidden due to flagging and it been enough time" do
        post.hidden = true
        post.hidden_at = (SiteSetting.cooldown_minutes_after_hiding_posts + 1).minutes.ago
        expect(Guardian.new(post.user)).to be_can_edit(post)
      end

      it "returns true if the post is hidden, it's been enough time and the edit window has expired" do
        post.hidden = true
        post.hidden_at = (SiteSetting.cooldown_minutes_after_hiding_posts + 1).minutes.ago
        post.created_at = (SiteSetting.post_edit_time_limit + 1).minutes.ago
        expect(Guardian.new(post.user)).to be_can_edit(post)
      end

      it "returns true if the post is hidden due to flagging and it's got a nil `hidden_at`" do
        post.hidden = true
        post.hidden_at = nil
        expect(Guardian.new(post.user)).to be_can_edit(post)
      end

      it 'returns false if you are trying to edit a post you soft deleted' do
        post.user_deleted = true
        expect(Guardian.new(post.user)).not_to be_can_edit(post)
      end

      it 'returns false if another regular user tries to edit a soft deleted wiki post' do
        post.wiki = true
        post.user_deleted = true
        expect(Guardian.new(coding_horror)).not_to be_can_edit(post)
      end

      it 'returns false if you are trying to edit a deleted post' do
        post.deleted_at = 1.day.ago
        expect(Guardian.new(post.user)).not_to be_can_edit(post)
      end

      it 'returns false if another regular user tries to edit a deleted wiki post' do
        post.wiki = true
        post.deleted_at = 1.day.ago
        expect(Guardian.new(coding_horror)).not_to be_can_edit(post)
      end

      it 'returns false if another regular user tries to edit your post' do
        expect(Guardian.new(coding_horror)).not_to be_can_edit(post)
      end

      it 'returns true if another regular user tries to edit wiki post' do
        post.wiki = true
        expect(Guardian.new(coding_horror)).to be_can_edit(post)
      end

      it "returns false if a wiki but the user can't create a post" do
        c = plain_category
        c.set_permissions(everyone: :readonly)
        c.save

        topic = Fabricate(:topic, category: c)
        post = Fabricate(:post, topic: topic)
        post.wiki = true

        expect(Guardian.new(user).can_edit?(post)).to eq(false)
      end

      it 'returns true as a moderator' do
        expect(Guardian.new(moderator)).to be_can_edit(post)
      end

      it 'returns true as a moderator, even if locked' do
        post.locked_by_id = admin.id
        expect(Guardian.new(moderator)).to be_can_edit(post)
      end

      it 'returns true as an admin' do
        expect(Guardian.new(admin)).to be_can_edit(post)
      end

      it 'returns true as a trust level 4 user' do
        expect(Guardian.new(trust_level_4)).to be_can_edit(post)
      end

      it 'returns false as a TL4 user if trusted_users_can_edit_others is false' do
        SiteSetting.trusted_users_can_edit_others = false
        expect(Guardian.new(trust_level_4).can_edit?(post)).to eq(false)
      end

      it 'returns false when trying to edit a topic with no trust' do
        SiteSetting.min_trust_to_edit_post = 2
        post.user.trust_level = 1

        expect(Guardian.new(topic.user)).not_to be_can_edit(topic)
      end

      it 'returns false when trying to edit a post with no trust' do
        SiteSetting.min_trust_to_edit_post = 2
        post.user.trust_level = 1

        expect(Guardian.new(post.user)).not_to be_can_edit(post)
      end

      it 'returns true when trying to edit a post with trust' do
        SiteSetting.min_trust_to_edit_post = 1
        post.user.trust_level = 1

        expect(Guardian.new(post.user)).to be_can_edit(post)
      end

      it 'returns false when another user has too low trust level to edit wiki post' do
        SiteSetting.min_trust_to_edit_wiki_post = 2
        post.wiki = true
        coding_horror.trust_level = 1

        expect(Guardian.new(coding_horror)).not_to be_can_edit(post)
      end

      it 'returns true when another user has adequate trust level to edit wiki post' do
        SiteSetting.min_trust_to_edit_wiki_post = 2
        post.wiki = true
        coding_horror.trust_level = 2

        expect(Guardian.new(coding_horror)).to be_can_edit(post)
      end

      it 'returns true for post author even when he has too low trust level to edit wiki post' do
        SiteSetting.min_trust_to_edit_wiki_post = 2
        post.wiki = true
        post.user.trust_level = 1

        expect(Guardian.new(post.user)).to be_can_edit(post)
      end

      context "shared drafts" do
        fab!(:category) { Fabricate(:category) }

        let(:topic) { Fabricate(:topic, category: category) }
        let(:post_with_draft) { Fabricate(:post, topic: topic) }

        before do
          SiteSetting.shared_drafts_category = category.id
          SiteSetting.shared_drafts_min_trust_level = '2'
          Fabricate(:shared_draft, topic: topic)
        end

        it 'returns true if a shared draft exists' do
          expect(Guardian.new(trust_level_2).can_edit_post?(post_with_draft)).to eq(true)
        end

        it 'returns false if the user has a lower trust level' do
          expect(Guardian.new(trust_level_1).can_edit_post?(post_with_draft)).to eq(false)
        end

        it 'returns false if the draft is from a different category' do
          topic.update!(category: Fabricate(:category))

          expect(Guardian.new(trust_level_2).can_edit_post?(post_with_draft)).to eq(false)
        end
      end

      context 'category group moderation is enabled' do
        fab!(:cat_mod_user) { Fabricate(:user) }

        before do
          SiteSetting.enable_category_group_moderation = true
          GroupUser.create!(group_id: group.id, user_id: cat_mod_user.id)
          post.topic.category.update!(reviewable_by_group_id: group.id)
        end

        it 'returns true as a category group moderator user' do
          expect(Guardian.new(cat_mod_user).can_edit?(post)).to eq(true)
        end

        it 'returns false for a regular user' do
          expect(Guardian.new(another_user).can_edit?(post)).to eq(false)
        end
      end

      describe 'post edit time limits' do

        context 'post is older than post_edit_time_limit' do
          let(:topic) { Fabricate(:topic) }
          let(:old_post) { Fabricate(:post, topic: topic, user: topic.user, created_at: 6.minutes.ago) }

          before do
            topic.user.update_columns(trust_level:  1)
            SiteSetting.post_edit_time_limit = 5
          end

          it 'returns false to the author of the post' do
            expect(Guardian.new(old_post.user)).not_to be_can_edit(old_post)
          end

          it 'returns true as a moderator' do
            expect(Guardian.new(moderator).can_edit?(old_post)).to eq(true)
          end

          it 'returns true as an admin' do
            expect(Guardian.new(admin).can_edit?(old_post)).to eq(true)
          end

          it 'returns false for another regular user trying to edit your post' do
            expect(Guardian.new(coding_horror)).not_to be_can_edit(old_post)
          end

          it 'returns true for another regular user trying to edit a wiki post' do
            old_post.wiki = true
            expect(Guardian.new(coding_horror)).to be_can_edit(old_post)
          end

          context "unlimited owner edits on first post" do
            let(:owner) { old_post.user }

            it "returns true when the post topic's category allow_unlimited_owner_edits_on_first_post" do
              old_post.topic.category.update(allow_unlimited_owner_edits_on_first_post: true)
              expect(Guardian.new(owner)).to be_can_edit(old_post)
            end

            it "returns false when the post topic's category does not allow_unlimited_owner_edits_on_first_post" do
              old_post.topic.category.update(allow_unlimited_owner_edits_on_first_post: false)
              expect(Guardian.new(owner)).not_to be_can_edit(old_post)
            end

            it "returns false when the post topic's category allow_unlimited_owner_edits_on_first_post but the post is not the first in the topic" do
              old_post.topic.category.update(allow_unlimited_owner_edits_on_first_post: true)
              new_post = Fabricate(:post, user: owner, topic: old_post.topic, created_at: 6.minutes.ago)
              expect(Guardian.new(owner)).not_to be_can_edit(new_post)
            end

            it "returns false when someone other than owner is editing and category allow_unlimited_owner_edits_on_first_post" do
              old_post.topic.category.update(allow_unlimited_owner_edits_on_first_post: false)
              expect(Guardian.new(coding_horror)).not_to be_can_edit(old_post)
            end
          end
        end

        context 'post is older than tl2_post_edit_time_limit' do
          let(:old_post) { build(:post, topic: topic, user: topic.user, created_at: 12.minutes.ago) }

          before do
            topic.user.update_columns(trust_level: 2)
            SiteSetting.tl2_post_edit_time_limit = 10
          end

          it 'returns false to the author of the post' do
            expect(Guardian.new(old_post.user)).not_to be_can_edit(old_post)
          end

          it 'returns true as a moderator' do
            expect(Guardian.new(moderator).can_edit?(old_post)).to eq(true)
          end

          it 'returns true as an admin' do
            expect(Guardian.new(admin).can_edit?(old_post)).to eq(true)
          end

          it 'returns false for another regular user trying to edit your post' do
            expect(Guardian.new(coding_horror)).not_to be_can_edit(old_post)
          end

          it 'returns true for another regular user trying to edit a wiki post' do
            old_post.wiki = true
            expect(Guardian.new(coding_horror)).to be_can_edit(old_post)
          end
        end
      end

      context "first post of a static page doc" do
        let!(:tos_topic) { Fabricate(:topic, user: Discourse.system_user) }
        let!(:tos_first_post) { build(:post, topic: tos_topic, user: tos_topic.user) }
        before { SiteSetting.tos_topic_id = tos_topic.id }

        it "restricts static doc posts" do
          expect(Guardian.new(build(:user))).not_to be_can_edit(tos_first_post)
          expect(Guardian.new(moderator)).not_to be_can_edit(tos_first_post)
          expect(Guardian.new(admin)).to be_can_edit(tos_first_post)
        end
      end
    end

    describe 'a Topic' do

      it 'returns false when not logged in' do
        expect(Guardian.new).not_to be_can_edit(topic)
      end

      it 'returns true for editing your own post' do
        expect(Guardian.new(topic.user).can_edit?(topic)).to eq(true)
      end

      it 'returns false as a regular user' do
        expect(Guardian.new(coding_horror)).not_to be_can_edit(topic)
      end

      context 'first post is hidden' do
        let!(:topic) { Fabricate(:topic, user: user) }
        let!(:post) { Fabricate(:post, topic: topic, user: topic.user, hidden: true, hidden_at: Time.zone.now) }

        it 'returns false for editing your own post while inside the cooldown window' do
          SiteSetting.cooldown_minutes_after_hiding_posts = 30

          expect(Guardian.new(topic.user).can_edit?(topic)).to eq(false)
        end
      end

      context "locked" do
        let(:post) { Fabricate(:post, locked_by_id: admin.id) }
        let(:topic) { post.topic }

        it "doesn't allow users to edit locked topics" do
          expect(Guardian.new(topic.user).can_edit?(topic)).to eq(false)
          expect(Guardian.new(admin).can_edit?(topic)).to eq(true)
        end
      end

      context 'not archived' do
        it 'returns true as a moderator' do
          expect(Guardian.new(moderator).can_edit?(topic)).to eq(true)
        end

        it 'returns true as an admin' do
          expect(Guardian.new(admin).can_edit?(topic)).to eq(true)
        end

        it 'returns true at trust level 3' do
          expect(Guardian.new(trust_level_3).can_edit?(topic)).to eq(true)
        end

        it 'is false at TL3, if `trusted_users_can_edit_others` is false' do
          SiteSetting.trusted_users_can_edit_others = false
          expect(Guardian.new(trust_level_3).can_edit?(topic)).to eq(false)
        end

        it "returns false when the category is read only" do
          topic.category.set_permissions(everyone: :readonly)
          topic.category.save

          expect(Guardian.new(trust_level_3).can_edit?(topic)).to eq(false)

          expect(Guardian.new(admin).can_edit?(topic)).to eq(true)

          expect(Guardian.new(moderator).can_edit?(post)).to eq(false)
          expect(Guardian.new(moderator).can_edit?(topic)).to eq(false)
        end

        it "returns false for trust level 3 if category is secured" do
          topic.category.set_permissions(everyone: :create_post, staff: :full)
          topic.category.save

          expect(Guardian.new(trust_level_3).can_edit?(topic)).to eq(false)
          expect(Guardian.new(admin).can_edit?(topic)).to eq(true)
          expect(Guardian.new(moderator).can_edit?(topic)).to eq(true)
        end
      end

      context 'private message' do
        it 'returns false at trust level 3' do
          topic.archetype = 'private_message'
          expect(Guardian.new(trust_level_3).can_edit?(topic)).to eq(false)
        end

        it 'returns false at trust level 4' do
          topic.archetype = 'private_message'
          expect(Guardian.new(trust_level_4).can_edit?(topic)).to eq(false)
        end
      end

      context 'archived' do
        let(:archived_topic) { build(:topic, user: user, archived: true) }

        it 'returns true as a moderator' do
          expect(Guardian.new(moderator)).to be_can_edit(archived_topic)
        end

        it 'returns true as an admin' do
          expect(Guardian.new(admin)).to be_can_edit(archived_topic)
        end

        it 'returns true at trust level 4' do
          expect(Guardian.new(trust_level_4)).to be_can_edit(archived_topic)
        end

        it 'is false at TL4, if `trusted_users_can_edit_others` is false' do
          SiteSetting.trusted_users_can_edit_others = false
          expect(Guardian.new(trust_level_4).can_edit?(archived_topic)).to eq(false)
        end

        it 'returns false at trust level 3' do
          expect(Guardian.new(trust_level_3)).not_to be_can_edit(archived_topic)
        end

        it 'returns false as a topic creator' do
          expect(Guardian.new(user)).not_to be_can_edit(archived_topic)
        end
      end

      context 'very old' do
        let(:old_topic) { build(:topic, user: user, created_at: 6.minutes.ago) }

        before { SiteSetting.post_edit_time_limit = 5 }

        it 'returns true as a moderator' do
          expect(Guardian.new(moderator)).to be_can_edit(old_topic)
        end

        it 'returns true as an admin' do
          expect(Guardian.new(admin)).to be_can_edit(old_topic)
        end

        it 'returns true at trust level 3' do
          expect(Guardian.new(trust_level_3)).to be_can_edit(old_topic)
        end

        it 'returns false as a topic creator' do
          expect(Guardian.new(user)).not_to be_can_edit(old_topic)
        end
      end
    end

    describe 'a Category' do
      it 'returns false when not logged in' do
        expect(Guardian.new).not_to be_can_edit(plain_category)
      end

      it 'returns false as a regular user' do
        expect(Guardian.new(plain_category.user)).not_to be_can_edit(plain_category)
      end

      it 'returns false as a moderator' do
        expect(Guardian.new(moderator)).not_to be_can_edit(plain_category)
      end

      it 'returns true as an admin' do
        expect(Guardian.new(admin)).to be_can_edit(plain_category)
      end
    end

    describe 'a User' do

      it 'returns false when not logged in' do
        expect(Guardian.new).not_to be_can_edit(user)
      end

      it 'returns false as a different user' do
        expect(Guardian.new(coding_horror)).not_to be_can_edit(user)
      end

      it 'returns true when trying to edit yourself' do
        expect(Guardian.new(user)).to be_can_edit(user)
      end

      it 'returns true as a moderator' do
        expect(Guardian.new(moderator)).to be_can_edit(user)
      end

      it 'returns true as an admin' do
        expect(Guardian.new(admin)).to be_can_edit(user)
      end
    end

  end

  context 'can_moderate?' do

    it 'returns false with a nil object' do
      expect(Guardian.new(user)).not_to be_can_moderate(nil)
    end

    context 'when user is silenced' do
      it 'returns false' do
        user.update_column(:silenced_till, 1.year.from_now)
        expect(Guardian.new(user).can_moderate?(post)).to be(false)
        expect(Guardian.new(user).can_moderate?(topic)).to be(false)
      end
    end

    context 'a Topic' do

      it 'returns false when not logged in' do
        expect(Guardian.new).not_to be_can_moderate(topic)
      end

      it 'returns false when not a moderator' do
        expect(Guardian.new(user)).not_to be_can_moderate(topic)
      end

      it 'returns true when a moderator' do
        expect(Guardian.new(moderator)).to be_can_moderate(topic)
      end

      it 'returns true when an admin' do
        expect(Guardian.new(admin)).to be_can_moderate(topic)
      end

      it 'returns true when trust level 4' do
        expect(Guardian.new(trust_level_4)).to be_can_moderate(topic)
      end

    end

  end

  context 'can_see_flags?' do

    it "returns false when there is no post" do
      expect(Guardian.new(moderator)).not_to be_can_see_flags(nil)
    end

    it "returns false when there is no user" do
      expect(Guardian.new(nil)).not_to be_can_see_flags(post)
    end

    it "allow regular users to see flags" do
      expect(Guardian.new(user)).not_to be_can_see_flags(post)
    end

    it "allows moderators to see flags" do
      expect(Guardian.new(moderator)).to be_can_see_flags(post)
    end

    it "allows moderators to see flags" do
      expect(Guardian.new(admin)).to be_can_see_flags(post)
    end
  end

  context "can_review_topic?" do
    it 'returns false with a nil object' do
      expect(Guardian.new(user).can_review_topic?(nil)).to eq(false)
    end

    it 'returns true for a staff user' do
      expect(Guardian.new(moderator).can_review_topic?(topic)).to eq(true)
    end

    it 'returns false for a regular user' do
      expect(Guardian.new(user).can_review_topic?(topic)).to eq(false)
    end

    it 'returns true for a group member with reviewable status' do
      SiteSetting.enable_category_group_moderation = true
      GroupUser.create!(group_id: group.id, user_id: user.id)
      topic.category.update!(reviewable_by_group_id: group.id)
      expect(Guardian.new(user).can_review_topic?(topic)).to eq(true)
    end
  end

  context "can_close_topic?" do
    it 'returns false with a nil object' do
      expect(Guardian.new(user).can_close_topic?(nil)).to eq(false)
    end

    it 'returns true for a staff user' do
      expect(Guardian.new(moderator).can_close_topic?(topic)).to eq(true)
    end

    it 'returns false for a regular user' do
      expect(Guardian.new(user).can_close_topic?(topic)).to eq(false)
    end

    it 'returns true for a group member with reviewable status' do
      SiteSetting.enable_category_group_moderation = true
      GroupUser.create!(group_id: group.id, user_id: user.id)
      topic.category.update!(reviewable_by_group_id: group.id)
      expect(Guardian.new(user).can_close_topic?(topic)).to eq(true)
    end
  end

  context "can_archive_topic?" do
    it 'returns false with a nil object' do
      expect(Guardian.new(user).can_archive_topic?(nil)).to eq(false)
    end

    it 'returns true for a staff user' do
      expect(Guardian.new(moderator).can_archive_topic?(topic)).to eq(true)
    end

    it 'returns false for a regular user' do
      expect(Guardian.new(user).can_archive_topic?(topic)).to eq(false)
    end

    it 'returns true for a group member with reviewable status' do
      SiteSetting.enable_category_group_moderation = true
      GroupUser.create!(group_id: group.id, user_id: user.id)
      topic.category.update!(reviewable_by_group_id: group.id)
      expect(Guardian.new(user).can_archive_topic?(topic)).to eq(true)
    end
  end

  context "can_edit_staff_notes?" do
    it 'returns false with a nil object' do
      expect(Guardian.new(user).can_edit_staff_notes?(nil)).to eq(false)
    end

    it 'returns true for a staff user' do
      expect(Guardian.new(moderator).can_edit_staff_notes?(topic)).to eq(true)
    end

    it 'returns false for a regular user' do
      expect(Guardian.new(user).can_edit_staff_notes?(topic)).to eq(false)
    end

    it 'returns true for a group member with reviewable status' do
      SiteSetting.enable_category_group_moderation = true
      GroupUser.create!(group_id: group.id, user_id: user.id)
      topic.category.update!(reviewable_by_group_id: group.id)
      expect(Guardian.new(user).can_edit_staff_notes?(topic)).to eq(true)
    end
  end

  context "can_create_topic?" do
    it 'returns true for staff user' do
      expect(Guardian.new(moderator).can_create_topic?(topic)).to eq(true)
    end

    it 'returns false for user with insufficient trust level' do
      SiteSetting.min_trust_to_create_topic = 3
      expect(Guardian.new(user).can_create_topic?(topic)).to eq(false)
    end

    it 'returns true for user with sufficient trust level' do
      SiteSetting.min_trust_to_create_topic = 3
      expect(Guardian.new(trust_level_4).can_create_topic?(topic)).to eq(true)
    end

    it 'returns false when posting in "uncategorized" is disabled and there is no other category available for posting' do
      SiteSetting.allow_uncategorized_topics = false

      plain_category.set_permissions(group => :readonly)
      plain_category.save
      expect(Guardian.new(user).can_create_topic?(topic)).to eq(false)
    end

    it 'returns true when there is a category available for posting' do
      SiteSetting.allow_uncategorized_topics = false

      plain_category.set_permissions(group => :full)
      plain_category.save
      group.add(user)
      group.save
      expect(Guardian.new(user).can_create_topic?(topic)).to eq(true)
    end
  end

  context 'can_move_posts?' do

    it 'returns false with a nil object' do
      expect(Guardian.new(user)).not_to be_can_move_posts(nil)
    end

    context 'a Topic' do

      it 'returns false when not logged in' do
        expect(Guardian.new).not_to be_can_move_posts(topic)
      end

      it 'returns false when not a moderator' do
        expect(Guardian.new(user)).not_to be_can_move_posts(topic)
      end

      it 'returns true when a moderator' do
        expect(Guardian.new(moderator)).to be_can_move_posts(topic)
      end

      it 'returns true when an admin' do
        expect(Guardian.new(admin)).to be_can_move_posts(topic)
      end

    end

  end

  context 'can_delete?' do

    it 'returns false with a nil object' do
      expect(Guardian.new(user)).not_to be_can_delete(nil)
    end

    context 'a Topic' do
      before do
        # pretend we have a real topic
        topic.id = 9999999
      end

      it 'returns false when not logged in' do
        expect(Guardian.new).not_to be_can_delete(topic)
      end

      it 'returns false when not a moderator' do
        expect(Guardian.new(user)).not_to be_can_delete(topic)
      end

      it 'returns true when a moderator' do
        expect(Guardian.new(moderator)).to be_can_delete(topic)
      end

      it 'returns true when an admin' do
        expect(Guardian.new(admin)).to be_can_delete(topic)
      end

      it 'returns false for static doc topics' do
        tos_topic = Fabricate(:topic, user: Discourse.system_user)
        SiteSetting.tos_topic_id = tos_topic.id
        expect(Guardian.new(admin)).not_to be_can_delete(tos_topic)
      end

      it "returns true for own topics" do
        topic.update_attribute(:posts_count, 1)
        topic.update_attribute(:created_at, Time.zone.now)
        expect(Guardian.new(topic.user)).to be_can_delete(topic)
      end

      it "returns false if topic has replies" do
        topic.update!(posts_count: 2, created_at: Time.zone.now)
        expect(Guardian.new(topic.user)).not_to be_can_delete(topic)
      end

      it "returns false if topic was created > 24h ago" do
        topic.update!(posts_count: 1, created_at: 48.hours.ago)
        expect(Guardian.new(topic.user)).not_to be_can_delete(topic)
      end

      context 'category group moderation is enabled' do
        fab!(:group_user) { Fabricate(:group_user) }

        before do
          SiteSetting.enable_category_group_moderation = true
        end

        it "returns false if user is not a member of the appropriate group" do
          expect(Guardian.new(group_user.user)).not_to be_can_delete(topic)
        end

        it "returns true if user is a member of the appropriate group" do
          topic.category.update!(reviewable_by_group_id: group_user.group.id)

          expect(Guardian.new(group_user.user)).to be_can_delete(topic)
        end
      end

    end

    context 'a Post' do

      before do
        post.post_number = 2
      end

      it 'returns false when not logged in' do
        expect(Guardian.new).not_to be_can_delete(post)
      end

      it "returns false when trying to delete your own post that has already been deleted" do
        post = Fabricate(:post)
        PostDestroyer.new(user, post).destroy
        post.reload
        expect(Guardian.new(user)).not_to be_can_delete(post)
      end

      it 'returns true when trying to delete your own post' do
        expect(Guardian.new(user)).to be_can_delete(post)

        expect(Guardian.new(trust_level_0)).not_to be_can_delete(post)
        expect(Guardian.new(trust_level_1)).not_to be_can_delete(post)
        expect(Guardian.new(trust_level_2)).not_to be_can_delete(post)
        expect(Guardian.new(trust_level_3)).not_to be_can_delete(post)
        expect(Guardian.new(trust_level_4)).not_to be_can_delete(post)
      end

      it 'returns false when self deletions are disabled' do
        SiteSetting.max_post_deletions_per_day = 0
        expect(Guardian.new(user)).not_to be_can_delete(post)
      end

      it "returns false when trying to delete another user's own post" do
        expect(Guardian.new(Fabricate(:user))).not_to be_can_delete(post)
      end

      it "returns false when it's the OP, even as a moderator if there are at least two posts" do
        post = Fabricate(:post)
        Fabricate(:post, topic: post.topic)
        expect(Guardian.new(moderator)).not_to be_can_delete(post)
      end

      it 'returns true when a moderator' do
        expect(Guardian.new(moderator)).to be_can_delete(post)
      end

      it 'returns true when an admin' do
        expect(Guardian.new(admin)).to be_can_delete(post)
      end

      it "returns true for category moderators" do
        SiteSetting.enable_category_group_moderation = true
        GroupUser.create(group: group, user: user)
        category = Fabricate(:category, reviewable_by_group_id: group.id)
        post.topic.update!(category: category)

        expect(Guardian.new(user).can_delete?(post)).to eq(true)
      end

      it 'returns false when post is first in a static doc topic' do
        tos_topic = Fabricate(:topic, user: Discourse.system_user)
        SiteSetting.tos_topic_id = tos_topic.id
        post.update_attribute :post_number, 1
        post.update_attribute :topic_id, tos_topic.id
        expect(Guardian.new(admin)).not_to be_can_delete(post)
      end

      context 'the topic is archived' do
        before do
          post.topic.archived = true
        end

        it "allows a staff member to delete it" do
          expect(Guardian.new(moderator)).to be_can_delete(post)
        end

        it "doesn't allow a regular user to delete it" do
          expect(Guardian.new(post.user)).not_to be_can_delete(post)
        end
      end

    end

    context 'a Category' do

      let(:category) { build(:category, user: moderator) }

      it 'returns false when not logged in' do
        expect(Guardian.new).not_to be_can_delete(category)
      end

      it 'returns false when a regular user' do
        expect(Guardian.new(user)).not_to be_can_delete(category)
      end

      it 'returns false when a moderator' do
        expect(Guardian.new(moderator)).not_to be_can_delete(category)
      end

      it 'returns true when an admin' do
        expect(Guardian.new(admin)).to be_can_delete(category)
      end

      it "can't be deleted if it has a forum topic" do
        category.topic_count = 10
        expect(Guardian.new(moderator)).not_to be_can_delete(category)
      end

      it "can't be deleted if it is the Uncategorized Category" do
        uncategorized_cat_id = SiteSetting.uncategorized_category_id
        uncategorized_category = Category.find(uncategorized_cat_id)
        expect(Guardian.new(admin)).not_to be_can_delete(uncategorized_category)
      end

      it "can't be deleted if it has children" do
        category.expects(:has_children?).returns(true)
        expect(Guardian.new(admin)).not_to be_can_delete(category)
      end

    end

    context 'can_suspend?' do
      it 'returns false when a user tries to suspend another user' do
        expect(Guardian.new(user)).not_to be_can_suspend(coding_horror)
      end

      it 'returns true when an admin tries to suspend another user' do
        expect(Guardian.new(admin)).to be_can_suspend(coding_horror)
      end

      it 'returns true when a moderator tries to suspend another user' do
        expect(Guardian.new(moderator)).to be_can_suspend(coding_horror)
      end

      it 'returns false when staff tries to suspend staff' do
        expect(Guardian.new(admin)).not_to be_can_suspend(moderator)
      end
    end

    context 'a PostAction' do
      let(:post_action) {
        user.id = 1
        post.id = 1

        a = PostAction.new(user: user, post: post, post_action_type_id: 2)
        a.created_at = 1.minute.ago
        a
      }

      it 'returns false when not logged in' do
        expect(Guardian.new).not_to be_can_delete(post_action)
      end

      it 'returns false when not the user who created it' do
        expect(Guardian.new(coding_horror)).not_to be_can_delete(post_action)
      end

      it "returns false if the window has expired" do
        post_action.created_at = 20.minutes.ago
        SiteSetting.post_undo_action_window_mins = 10
        expect(Guardian.new(user)).not_to be_can_delete(post_action)
      end

      it "returns true if it's yours" do
        expect(Guardian.new(user)).to be_can_delete(post_action)
      end

    end

  end

  context 'can_approve?' do

    it "wont allow a non-logged in user to approve" do
      expect(Guardian.new).not_to be_can_approve(user)
    end

    it "wont allow a non-admin to approve a user" do
      expect(Guardian.new(coding_horror)).not_to be_can_approve(user)
    end

    it "returns false when the user is already approved" do
      user.approved = true
      expect(Guardian.new(admin)).not_to be_can_approve(user)
    end

    it "returns false when the user is not active" do
      user.active = false
      expect(Guardian.new(admin)).not_to be_can_approve(user)
    end

    it "allows an admin to approve a user" do
      expect(Guardian.new(admin)).to be_can_approve(user)
    end

    it "allows a moderator to approve a user" do
      expect(Guardian.new(moderator)).to be_can_approve(user)
    end

  end

  context 'can_grant_admin?' do
    it "wont allow a non logged in user to grant an admin's access" do
      expect(Guardian.new).not_to be_can_grant_admin(another_admin)
    end

    it "wont allow a regular user to revoke an admin's access" do
      expect(Guardian.new(user)).not_to be_can_grant_admin(another_admin)
    end

    it 'wont allow an admin to grant their own access' do
      expect(Guardian.new(admin)).not_to be_can_grant_admin(admin)
    end

    it "allows an admin to grant a regular user access" do
      admin.id = 1
      user.id = 2
      expect(Guardian.new(admin)).to be_can_grant_admin(user)
    end

    it 'should not allow an admin to grant admin access to a non real user' do
      begin
        Discourse.system_user.update!(admin: false)
        expect(Guardian.new(admin).can_grant_admin?(Discourse.system_user)).to be(false)
      ensure
        Discourse.system_user.update!(admin: true)
      end
    end
  end

  context 'can_revoke_admin?' do
    it "wont allow a non logged in user to revoke an admin's access" do
      expect(Guardian.new).not_to be_can_revoke_admin(another_admin)
    end

    it "wont allow a regular user to revoke an admin's access" do
      expect(Guardian.new(user)).not_to be_can_revoke_admin(another_admin)
    end

    it 'wont allow an admin to revoke their own access' do
      expect(Guardian.new(admin)).not_to be_can_revoke_admin(admin)
    end

    it "allows an admin to revoke another admin's access" do
      admin.id = 1
      another_admin.id = 2

      expect(Guardian.new(admin)).to be_can_revoke_admin(another_admin)
    end

    it "should not allow an admin to revoke a no real user's admin access" do
      expect(Guardian.new(admin).can_revoke_admin?(Discourse.system_user)).to be(false)
    end
  end

  context 'can_grant_moderation?' do

    it "wont allow a non logged in user to grant an moderator's access" do
      expect(Guardian.new).not_to be_can_grant_moderation(user)
    end

    it "wont allow a regular user to revoke an moderator's access" do
      expect(Guardian.new(user)).not_to be_can_grant_moderation(moderator)
    end

    it 'will allow an admin to grant their own moderator access' do
      expect(Guardian.new(admin)).to be_can_grant_moderation(admin)
    end

    it 'wont allow an admin to grant it to an already moderator' do
      expect(Guardian.new(admin)).not_to be_can_grant_moderation(moderator)
    end

    it "allows an admin to grant a regular user access" do
      expect(Guardian.new(admin)).to be_can_grant_moderation(user)
    end

    it "should not allow an admin to grant moderation to a non real user" do
      begin
        Discourse.system_user.update!(moderator: false)
        expect(Guardian.new(admin).can_grant_moderation?(Discourse.system_user)).to be(false)
      ensure
        Discourse.system_user.update!(moderator: true)
      end
    end
  end

  context 'can_revoke_moderation?' do
    it "wont allow a non logged in user to revoke an moderator's access" do
      expect(Guardian.new).not_to be_can_revoke_moderation(moderator)
    end

    it "wont allow a regular user to revoke an moderator's access" do
      expect(Guardian.new(user)).not_to be_can_revoke_moderation(moderator)
    end

    it 'wont allow a moderator to revoke their own moderator' do
      expect(Guardian.new(moderator)).not_to be_can_revoke_moderation(moderator)
    end

    it "allows an admin to revoke a moderator's access" do
      expect(Guardian.new(admin)).to be_can_revoke_moderation(moderator)
    end

    it "allows an admin to revoke a moderator's access from self" do
      admin.moderator = true
      expect(Guardian.new(admin)).to be_can_revoke_moderation(admin)
    end

    it "does not allow revoke from non moderators" do
      expect(Guardian.new(admin)).not_to be_can_revoke_moderation(admin)
    end

    it "should not allow an admin to revoke moderation from a non real user" do
      expect(Guardian.new(admin).can_revoke_moderation?(Discourse.system_user)).to be(false)
    end
  end

  context "can_see_invite_details?" do

    it 'is false without a logged in user' do
      expect(Guardian.new(nil)).not_to be_can_see_invite_details(user)
    end

    it 'is false without a user to look at' do
      expect(Guardian.new(user)).not_to be_can_see_invite_details(nil)
    end

    it 'is true when looking at your own invites' do
      expect(Guardian.new(user)).to be_can_see_invite_details(user)
    end
  end

  context "can_access_forum?" do

    let(:unapproved_user) { Fabricate.build(:user) }

    context "when must_approve_users is false" do
      before do
        SiteSetting.must_approve_users = false
      end

      it "returns true for a nil user" do
        expect(Guardian.new(nil)).to be_can_access_forum
      end

      it "returns true for an unapproved user" do
        expect(Guardian.new(unapproved_user)).to be_can_access_forum
      end
    end

    context 'when must_approve_users is true' do
      before do
        SiteSetting.must_approve_users = true
      end

      it "returns false for a nil user" do
        expect(Guardian.new(nil)).not_to be_can_access_forum
      end

      it "returns false for an unapproved user" do
        expect(Guardian.new(unapproved_user)).not_to be_can_access_forum
      end

      it "returns true for an admin user" do
        unapproved_user.admin = true
        expect(Guardian.new(unapproved_user)).to be_can_access_forum
      end

      it "returns true for an approved user" do
        unapproved_user.approved = true
        expect(Guardian.new(unapproved_user)).to be_can_access_forum
      end

    end

  end

  describe "can_delete_all_posts?" do
    it "is false without a logged in user" do
      expect(Guardian.new(nil)).not_to be_can_delete_all_posts(user)
    end

    it "is false without a user to look at" do
      expect(Guardian.new(admin)).not_to be_can_delete_all_posts(nil)
    end

    it "is false for regular users" do
      expect(Guardian.new(user)).not_to be_can_delete_all_posts(coding_horror)
    end

    context "for moderators" do
      let(:actor) { moderator }

      it "is true if user has no posts" do
        SiteSetting.delete_user_max_post_age = 10
        expect(Guardian.new(actor)).to be_can_delete_all_posts(Fabricate(:user, created_at: 100.days.ago))
      end

      it "is true if user's first post is newer than delete_user_max_post_age days old" do
        user = Fabricate(:user, created_at: 100.days.ago)
        user.user_stat.update!(first_post_created_at: 9.days.ago)
        SiteSetting.delete_user_max_post_age = 10
        expect(Guardian.new(actor)).to be_can_delete_all_posts(user)
      end

      it "is false if user's first post is older than delete_user_max_post_age days old" do
        user = Fabricate(:user, created_at: 100.days.ago)
        user.user_stat.update!(first_post_created_at: 11.days.ago)
        SiteSetting.delete_user_max_post_age = 10
        expect(Guardian.new(actor)).not_to be_can_delete_all_posts(user)
      end

      it "is false if user is an admin" do
        expect(Guardian.new(actor)).not_to be_can_delete_all_posts(admin)
      end

      it "is true if number of posts is small" do
        user = Fabricate(:user, created_at: 1.day.ago)
        user.user_stat.update!(post_count: 1)
        SiteSetting.delete_all_posts_max = 10
        expect(Guardian.new(actor)).to be_can_delete_all_posts(user)
      end

      it "is false if number of posts is not small" do
        user = Fabricate(:user, created_at: 1.day.ago)
        user.user_stat.update!(post_count: 11)
        SiteSetting.delete_all_posts_max = 10
        expect(Guardian.new(actor)).not_to be_can_delete_all_posts(user)
      end
    end

    context "for admins" do
      let(:actor) { admin }

      it "is true if user has no posts" do
        SiteSetting.delete_user_max_post_age = 10
        expect(Guardian.new(actor)).to be_can_delete_all_posts(Fabricate(:user, created_at: 100.days.ago))
      end

      it "is true if user's first post is newer than delete_user_max_post_age days old" do
        user = Fabricate(:user, created_at: 100.days.ago)
        user.stubs(:first_post_created_at).returns(9.days.ago)
        SiteSetting.delete_user_max_post_age = 10
        expect(Guardian.new(actor)).to be_can_delete_all_posts(user)
      end

      it "is true if user's first post is older than delete_user_max_post_age days old" do
        user = Fabricate(:user, created_at: 100.days.ago)
        user.stubs(:first_post_created_at).returns(11.days.ago)
        SiteSetting.delete_user_max_post_age = 10
        expect(Guardian.new(actor)).to be_can_delete_all_posts(user)
      end

      it "is false if user is an admin" do
        expect(Guardian.new(actor)).not_to be_can_delete_all_posts(admin)
      end

      it "is true if number of posts is small" do
        u = Fabricate(:user, created_at: 1.day.ago)
        u.stubs(:post_count).returns(1)
        SiteSetting.delete_all_posts_max = 10
        expect(Guardian.new(actor)).to be_can_delete_all_posts(u)
      end

      it "is true if number of posts is not small" do
        u = Fabricate(:user, created_at: 1.day.ago)
        u.stubs(:post_count).returns(11)
        SiteSetting.delete_all_posts_max = 10
        expect(Guardian.new(actor)).to be_can_delete_all_posts(u)
      end
    end
  end

  describe "can_anonymize_user?" do
    it "is false without a logged in user" do
      expect(Guardian.new(nil)).not_to be_can_anonymize_user(user)
    end

    it "is false without a user to look at" do
      expect(Guardian.new(admin)).not_to be_can_anonymize_user(nil)
    end

    it "is false for a regular user" do
      expect(Guardian.new(user)).not_to be_can_anonymize_user(coding_horror)
    end

    it "is false for myself" do
      expect(Guardian.new(user)).not_to be_can_anonymize_user(user)
    end

    it "is true for admin anonymizing a regular user" do
      expect(Guardian.new(admin).can_anonymize_user?(user)).to eq(true)
    end

    it "is true for moderator anonymizing a regular user" do
      expect(Guardian.new(moderator).can_anonymize_user?(user)).to eq(true)
    end

    it "is false for admin anonymizing an admin" do
      expect(Guardian.new(admin)).not_to be_can_anonymize_user(Fabricate(:admin))
    end

    it "is false for admin anonymizing a moderator" do
      expect(Guardian.new(admin)).not_to be_can_anonymize_user(moderator)
    end

    it "is false for moderator anonymizing an admin" do
      expect(Guardian.new(moderator)).not_to be_can_anonymize_user(admin)
    end

    it "is false for moderator anonymizing a moderator" do
      expect(Guardian.new(moderator)).not_to be_can_anonymize_user(moderator)
    end
  end

  describe 'can_grant_title?' do
    it 'is false without a logged in user' do
      expect(Guardian.new(nil)).not_to be_can_grant_title(user)
    end

    it 'is false for regular users' do
      expect(Guardian.new(user)).not_to be_can_grant_title(user)
    end

    it 'is true for moderators' do
      expect(Guardian.new(moderator)).to be_can_grant_title(user)
    end

    it 'is true for admins' do
      expect(Guardian.new(admin)).to be_can_grant_title(user)
    end

    it 'is false without a user to look at' do
      expect(Guardian.new(admin)).not_to be_can_grant_title(nil)
    end

    context 'with title argument' do
      fab!(:title_badge) { Fabricate(:badge, name: 'Helper', allow_title: true) }
      fab!(:no_title_badge) { Fabricate(:badge, name: 'Writer', allow_title: false) }
      fab!(:group) { Fabricate(:group, title: 'Groupie') }

      it 'returns true if title belongs to a badge that user has' do
        BadgeGranter.grant(title_badge, user)
        expect(Guardian.new(user).can_grant_title?(user, title_badge.name)).to eq(true)
      end

      it "returns false if title belongs to a badge that user doesn't have" do
        expect(Guardian.new(user).can_grant_title?(user, title_badge.name)).to eq(false)
      end

      it "returns false if title belongs to a badge that user has but can't be used as a title" do
        BadgeGranter.grant(no_title_badge, user)
        expect(Guardian.new(user).can_grant_title?(user, no_title_badge.name)).to eq(false)
      end

      it 'returns true if title is from a group the user belongs to' do
        group.add(user)
        expect(Guardian.new(user).can_grant_title?(user, group.title)).to eq(true)
      end

      it "returns false if title is from a group the user doesn't belong to" do
        expect(Guardian.new(user).can_grant_title?(user, group.title)).to eq(false)
      end

      it "returns true if the title is set to an empty string" do
        expect(Guardian.new(user).can_grant_title?(user, '')).to eq(true)
      end
    end
  end

  describe 'can_use_primary_group?' do
    fab!(:group) { Fabricate(:group, title: 'Groupie') }

    it 'is false without a logged in user' do
      expect(Guardian.new(nil)).not_to be_can_use_primary_group(user)
    end

    it 'is false with no group_id' do
      user.update(groups: [group])
      expect(Guardian.new(user)).not_to be_can_use_primary_group(user, nil)
    end

    it 'is false if the group does not exist' do
      user.update(groups: [group])
      expect(Guardian.new(user)).not_to be_can_use_primary_group(user, Group.last.id + 1)
    end

    it 'is false if the user is not a part of the group' do
      user.update(groups: [])
      expect(Guardian.new(user)).not_to be_can_use_primary_group(user, group.id)
    end

    it 'is false if the group is automatic' do
      user.update(groups: [Group.new(name: 'autooo', automatic: true)])
      expect(Guardian.new(user)).not_to be_can_use_primary_group(user, group.id)
    end

    it 'is true if the user is a part of the group, and the group is custom' do
      user.update(groups: [group])
      expect(Guardian.new(user)).to be_can_use_primary_group(user, group.id)
    end
  end

  describe 'can_use_flair_group?' do
    fab!(:group) { Fabricate(:group, title: 'Groupie', flair_icon: 'icon') }

    it 'is false without a logged in user' do
      expect(Guardian.new(nil).can_use_flair_group?(user)).to eq(false)
    end

    it 'is false if the group does not exist' do
      expect(Guardian.new(user).can_use_flair_group?(user, nil)).to eq(false)
      expect(Guardian.new(user).can_use_flair_group?(user, Group.last.id + 1)).to eq(false)
    end

    it 'is false if the user is not a part of the group' do
      expect(Guardian.new(user).can_use_flair_group?(user, group.id)).to eq(false)
    end

    it 'is false if the group does not have a flair' do
      group.update(flair_icon: nil)
      expect(Guardian.new(user).can_use_flair_group?(user, group.id)).to eq(false)
    end

    it 'is true if the user is a part of the group and the group has a flair' do
      user.update(groups: [group])
      expect(Guardian.new(user).can_use_flair_group?(user, group.id)).to eq(true)
    end
  end

  describe 'can_change_trust_level?' do

    it 'is false without a logged in user' do
      expect(Guardian.new(nil)).not_to be_can_change_trust_level(user)
    end

    it 'is false for regular users' do
      expect(Guardian.new(user)).not_to be_can_change_trust_level(user)
    end

    it 'is true for moderators' do
      expect(Guardian.new(moderator)).to be_can_change_trust_level(user)
    end

    it 'is true for admins' do
      expect(Guardian.new(admin)).to be_can_change_trust_level(user)
    end
  end

  describe "can_edit_username?" do
    it "is false without a logged in user" do
      expect(Guardian.new(nil)).not_to be_can_edit_username(build(:user, created_at: 1.minute.ago))
    end

    it "is false for regular users to edit another user's username" do
      expect(Guardian.new(build(:user))).not_to be_can_edit_username(build(:user, created_at: 1.minute.ago))
    end

    shared_examples "staff can always change usernames" do
      it "is true for moderators" do
        expect(Guardian.new(moderator)).to be_can_edit_username(user)
      end

      it "is true for admins" do
        expect(Guardian.new(admin)).to be_can_edit_username(user)
      end

      it "is true for admins when changing anonymous username" do
        expect(Guardian.new(admin)).to be_can_edit_username(anonymous_user)
      end
    end

    context "for anonymous user" do
      before do
        SiteSetting.allow_anonymous_posting = true
      end

      it "is false" do
        expect(Guardian.new(anonymous_user)).not_to be_can_edit_username(anonymous_user)
      end
    end

    context 'for a new user' do
      fab!(:target_user) { Fabricate(:user, created_at: 1.minute.ago) }
      include_examples "staff can always change usernames"

      it "is true for the user to change their own username" do
        expect(Guardian.new(target_user)).to be_can_edit_username(target_user)
      end
    end

    context 'for an old user' do
      before do
        SiteSetting.username_change_period = 3
      end

      let(:target_user) { Fabricate(:user, created_at: 4.days.ago) }

      context 'with no posts' do
        include_examples "staff can always change usernames"
        it "is true for the user to change their own username" do
          expect(Guardian.new(target_user)).to be_can_edit_username(target_user)
        end
      end

      context 'with posts' do
        before { target_user.stubs(:post_count).returns(1) }
        include_examples "staff can always change usernames"
        it "is false for the user to change their own username" do
          expect(Guardian.new(target_user)).not_to be_can_edit_username(target_user)
        end
      end
    end

    context 'when editing is disabled in preferences' do
      before do
        SiteSetting.username_change_period = 0
      end

      include_examples "staff can always change usernames"

      it "is false for the user to change their own username" do
        expect(Guardian.new(user)).not_to be_can_edit_username(user)
      end
    end

    context 'when SSO username override is active' do
      before do
        SiteSetting.discourse_connect_url = "https://www.example.com/sso"
        SiteSetting.enable_discourse_connect = true
        SiteSetting.auth_overrides_username = true
      end

      it "is false for admins" do
        expect(Guardian.new(admin)).not_to be_can_edit_username(admin)
      end

      it "is false for moderators" do
        expect(Guardian.new(moderator)).not_to be_can_edit_username(moderator)
      end

      it "is false for users" do
        expect(Guardian.new(user)).not_to be_can_edit_username(user)
      end
    end
  end

  describe "can_edit_email?" do
    context 'when allowed in settings' do
      before do
        SiteSetting.email_editable = true
      end

      context "for anonymous user" do
        before do
          SiteSetting.allow_anonymous_posting = true
        end

        it "is false" do
          expect(Guardian.new(anonymous_user)).not_to be_can_edit_email(anonymous_user)
        end
      end

      it "is false when not logged in" do
        expect(Guardian.new(nil)).not_to be_can_edit_email(build(:user, created_at: 1.minute.ago))
      end

      it "is false for regular users to edit another user's email" do
        expect(Guardian.new(build(:user))).not_to be_can_edit_email(build(:user, created_at: 1.minute.ago))
      end

      it "is true for a regular user to edit their own email" do
        expect(Guardian.new(user)).to be_can_edit_email(user)
      end

      it "is true for moderators" do
        expect(Guardian.new(moderator)).to be_can_edit_email(user)
      end

      it "is true for admins" do
        expect(Guardian.new(admin)).to be_can_edit_email(user)
      end
    end

    context 'when not allowed in settings' do
      before do
        SiteSetting.email_editable = false
      end

      it "is false when not logged in" do
        expect(Guardian.new(nil)).not_to be_can_edit_email(build(:user, created_at: 1.minute.ago))
      end

      it "is false for regular users to edit another user's email" do
        expect(Guardian.new(build(:user))).not_to be_can_edit_email(build(:user, created_at: 1.minute.ago))
      end

      it "is false for a regular user to edit their own email" do
        expect(Guardian.new(user)).not_to be_can_edit_email(user)
      end

      it "is false for admins" do
        expect(Guardian.new(admin)).not_to be_can_edit_email(user)
      end

      it "is false for moderators" do
        expect(Guardian.new(moderator)).not_to be_can_edit_email(user)
      end
    end

    context 'when SSO email override is active' do
      before do
        SiteSetting.email_editable = false
        SiteSetting.discourse_connect_url = "https://www.example.com/sso"
        SiteSetting.enable_discourse_connect = true
        SiteSetting.auth_overrides_email = true
      end

      it "is false for admins" do
        expect(Guardian.new(admin)).not_to be_can_edit_email(admin)
      end

      it "is false for moderators" do
        expect(Guardian.new(moderator)).not_to be_can_edit_email(moderator)
      end

      it "is false for users" do
        expect(Guardian.new(user)).not_to be_can_edit_email(user)
      end
    end
  end

  describe 'can_edit_name?' do
    it 'is false without a logged in user' do
      expect(Guardian.new(nil)).not_to be_can_edit_name(build(:user, created_at: 1.minute.ago))
    end

    it "is false for regular users to edit another user's name" do
      expect(Guardian.new(build(:user))).not_to be_can_edit_name(build(:user, created_at: 1.minute.ago))
    end

    context "for anonymous user" do
      before do
        SiteSetting.allow_anonymous_posting = true
      end

      it "is false" do
        expect(Guardian.new(anonymous_user)).not_to be_can_edit_name(anonymous_user)
      end
    end

    context 'for a new user' do
      let(:target_user) { build(:user, created_at: 1.minute.ago) }

      it 'is true for the user to change their own name' do
        expect(Guardian.new(target_user)).to be_can_edit_name(target_user)
      end

      it 'is true for moderators' do
        expect(Guardian.new(moderator)).to be_can_edit_name(user)
      end

      it 'is true for admins' do
        expect(Guardian.new(admin)).to be_can_edit_name(user)
      end
    end

    context 'when name is disabled in preferences' do
      before do
        SiteSetting.enable_names = false
      end

      it 'is false for the user to change their own name' do
        expect(Guardian.new(user)).not_to be_can_edit_name(user)
      end

      it 'is false for moderators' do
        expect(Guardian.new(moderator)).not_to be_can_edit_name(user)
      end

      it 'is false for admins' do
        expect(Guardian.new(admin)).not_to be_can_edit_name(user)
      end
    end

    context 'when name is enabled in preferences' do
      before do
        SiteSetting.enable_names = true
      end

      context 'when SSO is disabled' do
        before do
          SiteSetting.enable_discourse_connect = false
          SiteSetting.auth_overrides_name = false
        end

        it 'is true for admins' do
          expect(Guardian.new(admin)).to be_can_edit_name(admin)
        end

        it 'is true for moderators' do
          expect(Guardian.new(moderator)).to be_can_edit_name(moderator)
        end

        it 'is true for users' do
          expect(Guardian.new(user)).to be_can_edit_name(user)
        end
      end

      context 'when SSO is enabled' do
        before do
          SiteSetting.discourse_connect_url = "https://www.example.com/sso"
          SiteSetting.enable_discourse_connect = true
        end

        context 'when SSO name override is active' do
          before do
            SiteSetting.auth_overrides_name = true
          end

          it 'is false for admins' do
            expect(Guardian.new(admin)).not_to be_can_edit_name(admin)
          end

          it 'is false for moderators' do
            expect(Guardian.new(moderator)).not_to be_can_edit_name(moderator)
          end

          it 'is false for users' do
            expect(Guardian.new(user)).not_to be_can_edit_name(user)
          end
        end

        context 'when SSO name override is not active' do
          before do
            SiteSetting.auth_overrides_name = false
          end

          it 'is true for admins' do
            expect(Guardian.new(admin)).to be_can_edit_name(admin)
          end

          it 'is true for moderators' do
            expect(Guardian.new(moderator)).to be_can_edit_name(moderator)
          end

          it 'is true for users' do
            expect(Guardian.new(user)).to be_can_edit_name(user)
          end
        end
      end
    end
  end

  describe '#can_export_entity?' do
    let(:anonymous_guardian) { Guardian.new }
    let(:user_guardian) { Guardian.new(user) }
    let(:moderator_guardian) { Guardian.new(moderator) }
    let(:admin_guardian) { Guardian.new(admin) }

    it 'only allows admins to export user_list' do
      expect(user_guardian).not_to be_can_export_entity('user_list')
      expect(moderator_guardian).not_to be_can_export_entity('user_list')
      expect(admin_guardian).to be_can_export_entity('user_list')
    end

    it 'allow moderators to export other admin entities' do
      expect(user_guardian).not_to be_can_export_entity('staff_action')
      expect(moderator_guardian).to be_can_export_entity('staff_action')
      expect(admin_guardian).to be_can_export_entity('staff_action')
    end

    it 'does not allow anonymous to export' do
      expect(anonymous_guardian).not_to be_can_export_entity('user_archive')
    end
  end

  describe '#can_ignore_user?' do
    before do
      SiteSetting.min_trust_level_to_allow_ignore = 1
    end

    let(:guardian) { Guardian.new(trust_level_2) }

    context "when ignored user is the same as guardian user" do
      it 'does not allow ignoring user' do
        expect(guardian.can_ignore_user?(trust_level_2)).to eq(false)
      end
    end

    context "when ignored user is a staff user" do
      let!(:admin) { Fabricate(:user, admin: true) }

      it 'does not allow ignoring user' do
        expect(guardian.can_ignore_user?(admin)).to eq(false)
      end
    end

    context "when ignored user is a normal user" do
      it 'allows ignoring user' do
        expect(guardian.can_ignore_user?(another_user)).to eq(true)
      end
    end

    context "when ignorer is staff" do
      let(:guardian) { Guardian.new(admin) }
      it 'allows ignoring user' do
        expect(guardian.can_ignore_user?(another_user)).to eq(true)
      end
    end

    context "when ignorer's trust level is below min_trust_level_to_allow_ignore" do
      let(:guardian) { Guardian.new(trust_level_0) }
      it 'does not allow ignoring user' do
        expect(guardian.can_ignore_user?(another_user)).to eq(false)
      end
    end

    context "when ignorer's trust level is equal to min_trust_level_to_allow_ignore site setting" do
      let(:guardian) { Guardian.new(trust_level_1) }
      it 'allows ignoring user' do
        expect(guardian.can_ignore_user?(another_user)).to eq(true)
      end
    end

    context "when ignorer's trust level is above min_trust_level_to_allow_ignore site setting" do
      let(:guardian) { Guardian.new(trust_level_3) }
      it 'allows ignoring user' do
        expect(guardian.can_ignore_user?(another_user)).to eq(true)
      end
    end
  end

  describe '#can_mute_user?' do

    let(:guardian) { Guardian.new(trust_level_1) }

    context "when muted user is the same as guardian user" do
      it 'does not allow muting user' do
        expect(guardian.can_mute_user?(trust_level_1)).to eq(false)
      end
    end

    context "when muted user is a staff user" do
      let!(:admin) { Fabricate(:user, admin: true) }

      it 'does not allow muting user' do
        expect(guardian.can_mute_user?(admin)).to eq(false)
      end
    end

    context "when muted user is a normal user" do
      it 'allows muting user' do
        expect(guardian.can_mute_user?(another_user)).to eq(true)
      end
    end

    context "when muter's trust level is below tl1" do
      let(:guardian) { Guardian.new(trust_level_0) }
      let!(:trust_level_0) { build(:user, trust_level: 0) }

      it 'does not allow muting user' do
        expect(guardian.can_mute_user?(another_user)).to eq(false)
      end
    end

    context "when muter is staff" do
      let(:guardian) { Guardian.new(admin) }

      it 'allows muting user' do
        expect(guardian.can_mute_user?(another_user)).to eq(true)
      end
    end

    context "when muters's trust level is tl1" do
      let(:guardian) { Guardian.new(trust_level_1) }

      it 'allows muting user' do
        expect(guardian.can_mute_user?(another_user)).to eq(true)
      end
    end
  end

  describe "#allow_themes?" do
    let!(:theme) { Fabricate(:theme) }
    let!(:theme2) { Fabricate(:theme) }

    context "allowlist mode" do
      before do
        global_setting :allowed_theme_repos, "  https://magic.com/repo.git, https://x.com/git"
      end

      it "should respect theme allowlisting" do
        r = RemoteTheme.create!(remote_url: "https://magic.com/repo.git")
        theme.update!(remote_theme_id: r.id)

        guardian = Guardian.new(admin)

        expect(guardian.allow_themes?([theme.id, theme2.id], include_preview: true)).to eq(false)

        expect(guardian.allow_themes?([theme.id], include_preview: true)).to eq(true)

        expect(guardian.allowed_theme_repo_import?('https://x.com/git')).to eq(true)
        expect(guardian.allowed_theme_repo_import?('https:/evil.com/git')).to eq(false)

      end
    end

    it "allows staff to use any themes" do
      expect(Guardian.new(moderator).allow_themes?([theme.id, theme2.id])).to eq(false)
      expect(Guardian.new(admin).allow_themes?([theme.id, theme2.id])).to eq(false)

      expect(Guardian.new(moderator).allow_themes?([theme.id, theme2.id], include_preview: true)).to eq(true)
      expect(Guardian.new(admin).allow_themes?([theme.id, theme2.id], include_preview: true)).to eq(true)
    end

    it "only allows normal users to use user-selectable themes or default theme" do
      user_guardian = Guardian.new(user)

      expect(user_guardian.allow_themes?([theme.id, theme2.id])).to eq(false)
      expect(user_guardian.allow_themes?([theme.id])).to eq(false)
      expect(user_guardian.allow_themes?([theme2.id])).to eq(false)

      theme.set_default!
      expect(user_guardian.allow_themes?([theme.id])).to eq(true)
      expect(user_guardian.allow_themes?([theme2.id])).to eq(false)
      expect(user_guardian.allow_themes?([theme.id, theme2.id])).to eq(false)

      theme2.update!(user_selectable: true)
      expect(user_guardian.allow_themes?([theme2.id])).to eq(true)
      expect(user_guardian.allow_themes?([theme2.id, theme.id])).to eq(false)
    end

    it "allows child themes to be only used with their parent" do
      user_guardian = Guardian.new(user)

      theme.update!(user_selectable: true)
      theme2.update!(user_selectable: true)
      expect(user_guardian.allow_themes?([theme.id, theme2.id])).to eq(false)

      theme2.update!(user_selectable: false, component: true)
      theme.add_relative_theme!(:child, theme2)
      expect(user_guardian.allow_themes?([theme.id, theme2.id])).to eq(true)
      expect(user_guardian.allow_themes?([theme2.id])).to eq(false)
    end
  end

  describe 'can_wiki?' do
    let(:post) { build(:post, created_at: 1.minute.ago) }

    it 'returns false for regular user' do
      expect(Guardian.new(coding_horror)).not_to be_can_wiki(post)
    end

    it "returns false when user does not satisfy trust level but owns the post" do
      own_post = Fabricate(:post, user: trust_level_2)
      expect(Guardian.new(trust_level_2)).not_to be_can_wiki(own_post)
    end

    it "returns false when user satisfies trust level but tries to wiki someone else's post" do
      SiteSetting.min_trust_to_allow_self_wiki = 2
      expect(Guardian.new(trust_level_2)).not_to be_can_wiki(post)
    end

    it 'returns true when user satisfies trust level and owns the post' do
      SiteSetting.min_trust_to_allow_self_wiki = 2
      own_post = Fabricate(:post, user: trust_level_2)
      expect(Guardian.new(trust_level_2)).to be_can_wiki(own_post)
    end

    it 'returns true for admin user' do
      expect(Guardian.new(admin)).to be_can_wiki(post)
    end

    it 'returns true for trust_level_4 user' do
      expect(Guardian.new(trust_level_4)).to be_can_wiki(post)
    end

    context 'post is older than post_edit_time_limit' do
      let(:old_post) { build(:post, user: trust_level_2, created_at: 6.minutes.ago) }
      before do
        SiteSetting.min_trust_to_allow_self_wiki = 2
        SiteSetting.tl2_post_edit_time_limit = 5
      end

      it 'returns false when user satisfies trust level and owns the post' do
        expect(Guardian.new(trust_level_2)).not_to be_can_wiki(old_post)
      end

      it 'returns true for admin user' do
        expect(Guardian.new(admin)).to be_can_wiki(old_post)
      end

      it 'returns true for trust_level_4 user' do
        expect(Guardian.new(trust_level_4)).to be_can_wiki(post)
      end
    end
  end

  describe "Tags" do
    context "tagging disabled" do
      before do
        SiteSetting.tagging_enabled = false
      end

      it "can_create_tag returns false" do
        expect(Guardian.new(admin)).not_to be_can_create_tag
      end

      it "can_admin_tags returns false" do
        expect(Guardian.new(admin)).not_to be_can_admin_tags
      end

      it "can_admin_tag_groups returns false" do
        expect(Guardian.new(admin)).not_to be_can_admin_tag_groups
      end
    end

    context "tagging is enabled" do
      before do
        SiteSetting.tagging_enabled = true
        SiteSetting.min_trust_level_to_tag_topics = 1
      end

      context 'min_trust_to_create_tag is 3' do
        before do
          SiteSetting.min_trust_to_create_tag = 3
        end

        describe "can_create_tag" do
          it "returns false if trust level is too low" do
            expect(Guardian.new(trust_level_2)).not_to be_can_create_tag
          end

          it "returns true if trust level is high enough" do
            expect(Guardian.new(trust_level_3)).to be_can_create_tag
          end

          it "returns true for staff" do
            expect(Guardian.new(admin)).to be_can_create_tag
            expect(Guardian.new(moderator)).to be_can_create_tag
          end
        end

        describe "can_tag_topics" do
          it "returns false if trust level is too low" do
            expect(Guardian.new(Fabricate(:user, trust_level: 0))).not_to be_can_tag_topics
          end

          it "returns true if trust level is high enough" do
            expect(Guardian.new(Fabricate(:user, trust_level: 1))).to be_can_tag_topics
          end

          it "returns true for staff" do
            expect(Guardian.new(admin)).to be_can_tag_topics
            expect(Guardian.new(moderator)).to be_can_tag_topics
          end
        end
      end

      context 'min_trust_to_create_tag is "staff"' do
        before do
          SiteSetting.min_trust_to_create_tag = 'staff'
        end

        it "returns false if not staff" do
          expect(Guardian.new(trust_level_4).can_create_tag?).to eq(false)
        end

        it "returns true if staff" do
          expect(Guardian.new(admin)).to be_can_create_tag
          expect(Guardian.new(moderator)).to be_can_create_tag
        end
      end

      context 'min_trust_to_create_tag is "admin"' do
        before do
          SiteSetting.min_trust_to_create_tag = 'admin'
        end

        it "returns false if not admin" do
          expect(Guardian.new(trust_level_4).can_create_tag?).to eq(false)
          expect(Guardian.new(moderator).can_create_tag?).to eq(false)
        end

        it "returns true if admin" do
          expect(Guardian.new(admin)).to be_can_create_tag
        end
      end
    end
  end

  describe(:can_see_group) do
    it 'Correctly handles owner visible groups' do
      group = Group.new(name: 'group', visibility_level: Group.visibility_levels[:owners])

      group.add(member)
      group.save!

      group.add_owner(owner)
      group.reload

      expect(Guardian.new(admin).can_see_group?(group)).to eq(true)
      expect(Guardian.new(another_user).can_see_group?(group)).to eq(false)
      expect(Guardian.new(moderator).can_see_group?(group)).to eq(false)
      expect(Guardian.new(member).can_see_group?(group)).to eq(false)
      expect(Guardian.new.can_see_group?(group)).to eq(false)
      expect(Guardian.new(owner).can_see_group?(group)).to eq(true)
    end

    it 'Correctly handles staff visible groups' do
      group = Group.new(name: 'group', visibility_level: Group.visibility_levels[:staff])

      group.add(member)
      group.save!

      group.add_owner(owner)
      group.reload

      expect(Guardian.new(another_user).can_see_group?(group)).to eq(false)
      expect(Guardian.new(member).can_see_group?(group)).to eq(false)
      expect(Guardian.new(admin).can_see_group?(group)).to eq(true)
      expect(Guardian.new(moderator).can_see_group?(group)).to eq(true)
      expect(Guardian.new(owner).can_see_group?(group)).to eq(true)
      expect(Guardian.new.can_see_group?(group)).to eq(false)
    end

    it 'Correctly handles member visible groups' do
      group = Group.new(name: 'group', visibility_level: Group.visibility_levels[:members])

      group.add(member)
      group.save!

      group.add_owner(owner)
      group.reload

      expect(Guardian.new(moderator).can_see_group?(group)).to eq(true)
      expect(Guardian.new.can_see_group?(group)).to eq(false)
      expect(Guardian.new(another_user).can_see_group?(group)).to eq(false)
      expect(Guardian.new(admin).can_see_group?(group)).to eq(true)
      expect(Guardian.new(member).can_see_group?(group)).to eq(true)
      expect(Guardian.new(owner).can_see_group?(group)).to eq(true)
    end

    it 'Correctly handles logged-on-user visible groups' do
      group = Group.new(name: 'group', visibility_level: Group.visibility_levels[:logged_on_users])
      group.add(member)
      group.save!

      group.add_owner(owner)
      group.reload

      expect(Guardian.new.can_see_group?(group)).to eq(false)
      expect(Guardian.new(moderator).can_see_group?(group)).to eq(true)
      expect(Guardian.new(admin).can_see_group?(group)).to eq(true)
      expect(Guardian.new(member).can_see_group?(group)).to eq(true)
      expect(Guardian.new(owner).can_see_group?(group)).to eq(true)
      expect(Guardian.new(another_user).can_see_group?(group)).to eq(true)
    end

    it 'Correctly handles public groups' do
      group = Group.new(name: 'group', visibility_level: Group.visibility_levels[:public])

      expect(Guardian.new.can_see_group?(group)).to eq(true)
    end

  end

  describe(:can_see_group_members) do
    it 'Correctly handles group members visibility for owner' do
      group = Group.new(name: 'group', members_visibility_level: Group.visibility_levels[:owners])

      group.add(member)
      group.save!

      group.add_owner(owner)
      group.reload

      expect(Guardian.new(admin).can_see_group_members?(group)).to eq(true)
      expect(Guardian.new(another_user).can_see_group_members?(group)).to eq(false)
      expect(Guardian.new(moderator).can_see_group_members?(group)).to eq(false)
      expect(Guardian.new(member).can_see_group_members?(group)).to eq(false)
      expect(Guardian.new.can_see_group_members?(group)).to eq(false)
      expect(Guardian.new(owner).can_see_group_members?(group)).to eq(true)
    end

    it 'Correctly handles group members visibility for staff' do
      group = Group.new(name: 'group', members_visibility_level: Group.visibility_levels[:staff])

      group.add(member)
      group.save!

      group.add_owner(owner)
      group.reload

      expect(Guardian.new(another_user).can_see_group_members?(group)).to eq(false)
      expect(Guardian.new(member).can_see_group_members?(group)).to eq(false)
      expect(Guardian.new(admin).can_see_group_members?(group)).to eq(true)
      expect(Guardian.new(moderator).can_see_group_members?(group)).to eq(true)
      expect(Guardian.new(owner).can_see_group_members?(group)).to eq(true)
      expect(Guardian.new.can_see_group_members?(group)).to eq(false)
    end

    it 'Correctly handles group members visibility for member' do
      group = Group.new(name: 'group', members_visibility_level: Group.visibility_levels[:members])

      group.add(member)
      group.save!

      group.add_owner(owner)
      group.reload

      expect(Guardian.new(moderator).can_see_group_members?(group)).to eq(true)
      expect(Guardian.new.can_see_group_members?(group)).to eq(false)
      expect(Guardian.new(another_user).can_see_group_members?(group)).to eq(false)
      expect(Guardian.new(admin).can_see_group_members?(group)).to eq(true)
      expect(Guardian.new(member).can_see_group_members?(group)).to eq(true)
      expect(Guardian.new(owner).can_see_group_members?(group)).to eq(true)
    end

    it 'Correctly handles group members visibility for logged-on-user' do
      group = Group.new(name: 'group', members_visibility_level: Group.visibility_levels[:logged_on_users])
      group.add(member)
      group.save!

      group.add_owner(owner)
      group.reload

      expect(Guardian.new.can_see_group_members?(group)).to eq(false)
      expect(Guardian.new(moderator).can_see_group_members?(group)).to eq(true)
      expect(Guardian.new(admin).can_see_group_members?(group)).to eq(true)
      expect(Guardian.new(member).can_see_group_members?(group)).to eq(true)
      expect(Guardian.new(owner).can_see_group_members?(group)).to eq(true)
      expect(Guardian.new(another_user).can_see_group_members?(group)).to eq(true)
    end

    it 'Correctly handles group members visibility for public' do
      group = Group.new(name: 'group', members_visibility_level: Group.visibility_levels[:public])

      expect(Guardian.new.can_see_group_members?(group)).to eq(true)
    end

  end

  describe '#can_see_groups?' do
    it 'correctly handles owner visible groups' do
      group = Group.new(name: 'group', visibility_level: Group.visibility_levels[:owners])

      group.add(member)
      group.save!

      group.add_owner(owner)
      group.reload

      expect(Guardian.new(admin).can_see_groups?([group])).to eq(true)
      expect(Guardian.new(another_user).can_see_groups?([group])).to eq(false)
      expect(Guardian.new(moderator).can_see_groups?([group])).to eq(false)
      expect(Guardian.new(member).can_see_groups?([group])).to eq(false)
      expect(Guardian.new.can_see_groups?([group])).to eq(false)
      expect(Guardian.new(owner).can_see_groups?([group])).to eq(true)
    end

    it 'correctly handles the case where the user does not own every group' do
      group = Group.new(name: 'group', visibility_level: Group.visibility_levels[:owners])
      group2 = Group.new(name: 'group2', visibility_level: Group.visibility_levels[:owners])
      group2.save!

      group.add(member)
      group.save!

      group.add_owner(owner)
      group.reload

      expect(Guardian.new(admin).can_see_groups?([group, group2])).to eq(true)
      expect(Guardian.new(moderator).can_see_groups?([group, group2])).to eq(false)
      expect(Guardian.new(member).can_see_groups?([group, group2])).to eq(false)
      expect(Guardian.new.can_see_groups?([group, group2])).to eq(false)
      expect(Guardian.new(owner).can_see_groups?([group, group2])).to eq(false)
      expect(Guardian.new(another_user).can_see_groups?([group, group2])).to eq(false)
    end

    it 'correctly handles staff visible groups' do
      group = Group.new(name: 'group', visibility_level: Group.visibility_levels[:staff])

      group.add(member)
      group.save!

      group.add_owner(owner)
      group.reload

      expect(Guardian.new(member).can_see_groups?([group])).to eq(false)
      expect(Guardian.new(admin).can_see_groups?([group])).to eq(true)
      expect(Guardian.new(moderator).can_see_groups?([group])).to eq(true)
      expect(Guardian.new(owner).can_see_groups?([group])).to eq(true)
      expect(Guardian.new.can_see_groups?([group])).to eq(false)
      expect(Guardian.new(another_user).can_see_groups?([group])).to eq(false)
    end

    it 'correctly handles member visible groups' do
      group = Group.new(name: 'group', visibility_level: Group.visibility_levels[:members])

      group.add(member)
      group.save!

      group.add_owner(owner)
      group.reload

      expect(Guardian.new(another_user).can_see_groups?([group])).to eq(false)
      expect(Guardian.new(moderator).can_see_groups?([group])).to eq(true)
      expect(Guardian.new.can_see_groups?([group])).to eq(false)
      expect(Guardian.new(admin).can_see_groups?([group])).to eq(true)
      expect(Guardian.new(member).can_see_groups?([group])).to eq(true)
      expect(Guardian.new(owner).can_see_groups?([group])).to eq(true)
    end

    it 'correctly handles logged-on-user visible groups' do
      group = Group.new(name: 'group', visibility_level: Group.visibility_levels[:logged_on_users])

      group.add(member)
      group.save!

      group.add_owner(owner)
      group.reload

      expect(Guardian.new(member).can_see_groups?([group])).to eq(true)
      expect(Guardian.new(admin).can_see_groups?([group])).to eq(true)
      expect(Guardian.new(moderator).can_see_groups?([group])).to eq(true)
      expect(Guardian.new(owner).can_see_groups?([group])).to eq(true)
      expect(Guardian.new.can_see_groups?([group])).to eq(false)
      expect(Guardian.new(another_user).can_see_groups?([group])).to eq(true)
    end

    it 'correctly handles the case where the user is not a member of every group' do
      group1 = Group.new(name: 'group', visibility_level: Group.visibility_levels[:members])
      group2 = Group.new(name: 'group2', visibility_level: Group.visibility_levels[:members])
      group2.save!

      group1.add(member)
      group1.save!

      group1.add_owner(owner)
      group1.reload

      expect(Guardian.new(moderator).can_see_groups?([group1, group2])).to eq(true)
      expect(Guardian.new.can_see_groups?([group1, group2])).to eq(false)
      expect(Guardian.new(admin).can_see_groups?([group1, group2])).to eq(true)
      expect(Guardian.new(member).can_see_groups?([group1, group2])).to eq(false)
      expect(Guardian.new(owner).can_see_groups?([group1, group2])).to eq(false)
    end

    it 'correctly handles public groups' do
      group = Group.new(name: 'group', visibility_level: Group.visibility_levels[:public])

      expect(Guardian.new.can_see_groups?([group])).to eq(true)
    end

    it 'correctly handles case where not every group is public' do
      group1 = Group.new(name: 'group', visibility_level: Group.visibility_levels[:public])
      group2 = Group.new(name: 'group', visibility_level: Group.visibility_levels[:private])

      expect(Guardian.new.can_see_groups?([group1, group2])).to eq(false)
    end
  end

  context 'topic featured link category restriction' do
    before { SiteSetting.topic_featured_link_enabled = true }
    let(:guardian) { Guardian.new(user) }
    let(:uncategorized) { Category.find(SiteSetting.uncategorized_category_id) }

    context "uncategorized" do
      fab!(:link_category) { Fabricate(:link_category) }

      it "allows featured links if uncategorized allows it" do
        uncategorized.topic_featured_link_allowed = true
        uncategorized.save!
        expect(guardian.can_edit_featured_link?(nil)).to eq(true)
      end

      it "forbids featured links if uncategorized forbids it" do
        uncategorized.topic_featured_link_allowed = false
        uncategorized.save!
        expect(guardian.can_edit_featured_link?(nil)).to eq(false)
      end
    end

    context 'when exist' do
      fab!(:category) { Fabricate(:category, topic_featured_link_allowed: false) }
      fab!(:link_category) { Fabricate(:link_category) }

      it 'returns true if the category is listed' do
        expect(guardian.can_edit_featured_link?(link_category.id)).to eq(true)
      end

      it 'returns false if the category does not allow it' do
        expect(guardian.can_edit_featured_link?(category.id)).to eq(false)
      end
    end
  end

  context "suspension reasons" do
    it "will be shown by default" do
      expect(Guardian.new.can_see_suspension_reason?(user)).to eq(true)
    end

    context "with hide suspension reason enabled" do
      before do
        SiteSetting.hide_suspension_reasons = true
      end

      it "will not be shown to anonymous users" do
        expect(Guardian.new.can_see_suspension_reason?(user)).to eq(false)
      end

      it "users can see their own suspensions" do
        expect(Guardian.new(user).can_see_suspension_reason?(user)).to eq(true)
      end

      it "staff can see suspensions" do
        expect(Guardian.new(moderator).can_see_suspension_reason?(user)).to eq(true)
      end
    end
  end

  describe '#can_remove_allowed_users?' do
    context 'staff users' do
      it 'should be true' do
        expect(Guardian.new(moderator).can_remove_allowed_users?(topic))
          .to eq(true)
      end
    end

    context 'trust_level >= 2 user' do
      fab!(:topic_creator) { build(:user, trust_level: 2) }
      fab!(:topic) { Fabricate(:topic, user: topic_creator) }

      before do
        topic.allowed_users << topic_creator
        topic.allowed_users << another_user
      end

      it 'should be true' do
        expect(Guardian.new(topic_creator).can_remove_allowed_users?(topic))
          .to eq(true)
      end
    end

    context 'normal user' do
      fab!(:topic) { Fabricate(:topic, user: Fabricate(:user, trust_level: 1)) }

      before do
        topic.allowed_users << user
        topic.allowed_users << another_user
      end

      it 'should be false' do
        expect(Guardian.new(user).can_remove_allowed_users?(topic))
          .to eq(false)
      end

      describe 'target_user is the user' do
        describe 'when user is in a pm with another user' do
          it 'should return true' do
            expect(Guardian.new(user).can_remove_allowed_users?(topic, user))
              .to eq(true)
          end
        end

        describe 'when user is the creator of the topic' do
          it 'should return false' do
            expect(Guardian.new(topic.user).can_remove_allowed_users?(topic, topic.user))
              .to eq(false)
          end
        end

        describe 'when user is the only user in the topic' do
          it 'should return false' do
            topic.remove_allowed_user(Discourse.system_user, another_user.username)

            expect(Guardian.new(user).can_remove_allowed_users?(topic, user))
              .to eq(false)
          end
        end
      end

      describe 'target_user is not the user' do
        it 'should return false' do
          expect(Guardian.new(user).can_remove_allowed_users?(topic, moderator))
            .to eq(false)
        end
      end
    end

    context "anonymous users" do
      fab!(:topic) { Fabricate(:topic) }

      it 'should be false' do
        expect(Guardian.new.can_remove_allowed_users?(topic)).to eq(false)
      end

      it 'should be false when the topic does not have a user (for example because the user was removed)' do
        DB.exec("UPDATE topics SET user_id=NULL WHERE id=#{topic.id}")
        topic.reload

        expect(Guardian.new.can_remove_allowed_users?(topic)).to eq(false)
      end
    end
  end

  describe '#auth_token' do
    it 'returns the correct auth token' do
      token = UserAuthToken.generate!(user_id: user.id)
      cookie = create_auth_cookie(
        token: token.unhashed_auth_token,
        user_id: user.id,
        trust_level: user.trust_level,
        issued_at: 5.minutes.ago,
      )
      env = create_request_env(path: "/").merge("HTTP_COOKIE" => "_t=#{cookie};")

      guardian = Guardian.new(user, ActionDispatch::Request.new(env))
      expect(guardian.auth_token).to eq(token.auth_token)
    end

    it 'supports v0 of auth cookie' do
      token = UserAuthToken.generate!(user_id: user.id)
      cookie = token.unhashed_auth_token
      env = create_request_env(path: "/").merge("HTTP_COOKIE" => "_t=#{cookie};")

      guardian = Guardian.new(user, ActionDispatch::Request.new(env))
      expect(guardian.auth_token).to eq(token.auth_token)
    end
  end

  describe "can_publish_page?" do
    context "when disabled" do
      it "is false for staff" do
        expect(Guardian.new(admin).can_publish_page?(topic)).to eq(false)
      end
    end

    context "when enabled" do
      before do
        SiteSetting.enable_page_publishing = true
      end

      it "is false for anonymous users" do
        expect(Guardian.new.can_publish_page?(topic)).to eq(false)
      end

      it "is false for regular users" do
        expect(Guardian.new(user).can_publish_page?(topic)).to eq(false)
      end

      it "is true for staff" do
        expect(Guardian.new(moderator).can_publish_page?(topic)).to eq(true)
        expect(Guardian.new(admin).can_publish_page?(topic)).to eq(true)
      end

      it "is false if the topic is a private message" do
        post = Fabricate(:private_message_post, user: admin)
        expect(Guardian.new(admin).can_publish_page?(post.topic)).to eq(false)
      end

      context "when secure_media is also enabled" do
        before do
          setup_s3
          SiteSetting.secure_media = true
        end

        it "is false for everyone" do
          expect(Guardian.new(moderator).can_publish_page?(topic)).to eq(false)
          expect(Guardian.new(user).can_publish_page?(topic)).to eq(false)
          expect(Guardian.new.can_publish_page?(topic)).to eq(false)
          expect(Guardian.new(admin).can_publish_page?(topic)).to eq(false)
        end
      end
    end
  end

  describe "can_see_site_contact_details" do
    context "login_required is enabled" do
      before do
        SiteSetting.login_required = true
      end

      it "is false for anonymous users" do
        expect(Guardian.new.can_see_site_contact_details?).to eq(false)
      end

      it "is true for regular users" do
        expect(Guardian.new(user).can_see_site_contact_details?).to eq(true)
      end
    end

    context "login_required is disabled" do
      before do
        SiteSetting.login_required = false
      end

      it "is true for anonymous users" do
        expect(Guardian.new.can_see_site_contact_details?).to eq(true)
      end

      it "is true for regular users" do
        expect(Guardian.new(user).can_see_site_contact_details?).to eq(true)
      end
    end
  end

  describe "#can_mention_here?" do
    it 'returns false if disabled' do
      SiteSetting.max_here_mentioned = 0
      expect(admin.guardian.can_mention_here?).to eq(false)
    end

    it 'returns false if disabled' do
      SiteSetting.here_mention = ''
      expect(admin.guardian.can_mention_here?).to eq(false)
    end

    it 'works with trust levels' do
      SiteSetting.min_trust_level_for_here_mention = 2

      expect(trust_level_0.guardian.can_mention_here?).to eq(false)
      expect(trust_level_1.guardian.can_mention_here?).to eq(false)
      expect(trust_level_2.guardian.can_mention_here?).to eq(true)
      expect(trust_level_3.guardian.can_mention_here?).to eq(true)
      expect(trust_level_4.guardian.can_mention_here?).to eq(true)
      expect(moderator.guardian.can_mention_here?).to eq(true)
      expect(admin.guardian.can_mention_here?).to eq(true)
    end

    it 'works with staff' do
      SiteSetting.min_trust_level_for_here_mention = 'staff'

      expect(trust_level_4.guardian.can_mention_here?).to eq(false)
      expect(moderator.guardian.can_mention_here?).to eq(true)
      expect(admin.guardian.can_mention_here?).to eq(true)
    end

    it 'works with admin' do
      SiteSetting.min_trust_level_for_here_mention = 'admin'

      expect(trust_level_4.guardian.can_mention_here?).to eq(false)
      expect(moderator.guardian.can_mention_here?).to eq(false)
      expect(admin.guardian.can_mention_here?).to eq(true)
    end
  end
end
