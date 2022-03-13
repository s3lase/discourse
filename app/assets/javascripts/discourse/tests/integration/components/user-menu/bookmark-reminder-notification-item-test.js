import componentTest, {
  setupRenderingTest,
} from "discourse/tests/helpers/component-test";
import { discourseModule, query } from "discourse/tests/helpers/qunit-helpers";
import { deepMerge } from "discourse-common/lib/object";
import { NOTIFICATION_TYPES } from "discourse/tests/fixtures/concerns/notification-types";
import Notification from "discourse/models/notification";
import hbs from "htmlbars-inline-precompile";
import I18n from "I18n";

function getNotification(overrides = {}) {
  return Notification.create(
    deepMerge(
      {
        id: 11,
        user_id: 1,
        notification_type: NOTIFICATION_TYPES.bookmark_reminder,
        read: false,
        high_priority: true,
        created_at: "2022-07-01T06:00:32.173Z",
        post_number: 113,
        topic_id: 449,
        fancy_title: "This is fancy title &lt;a&gt;!",
        slug: "this-is-fancy-title",
        data: {
          title: "this is unsafe bookmark title <a>!",
          display_username: "osama",
          bookmark_name: null,
          bookmarkable_url: "/t/sometopic/3232",
        },
      },
      overrides
    )
  );
}

discourseModule(
  "Integration | Component | user-menu | bookmark-reminder-notification-item",
  function (hooks) {
    setupRenderingTest(hooks);

    const template = hbs`<UserMenu::BookmarkReminderNotificationItem @item={{this.notification}}/>`;

    componentTest("when the bookmark has a name", {
      template,

      beforeEach() {
        this.set(
          "notification",
          getNotification({ data: { bookmark_name: "MY BOOKMARK" } })
        );
      },

      async test(assert) {
        const link = query("li a");
        assert.strictEqual(
          link.title,
          I18n.t("notifications.titles.bookmark_reminder_with_name", {
            name: "MY BOOKMARK",
          }),
          "the notification has a title that includes the bookmark name"
        );
      },
    });

    componentTest("when the bookmark doesn't have a name", {
      template,

      beforeEach() {
        this.set(
          "notification",
          getNotification({ data: { bookmark_name: null } })
        );
      },

      async test(assert) {
        const link = query("li a");
        assert.strictEqual(
          link.title,
          I18n.t("notifications.titles.bookmark_reminder"),
          "the notification has a generic title"
        );
      },
    });

    componentTest(
      "when the bookmark reminder doesn't originate from a topic and has a title",
      {
        template,

        beforeEach() {
          this.set(
            "notification",
            getNotification({
              post_number: null,
              topic_id: null,
              fancy_title: null,
              data: {
                title: "this is unsafe bookmark title <a>!",
                bookmarkable_url: "/chat/channel/33",
              },
            })
          );
        },

        async test(assert) {
          const description = query("li span:nth-of-type(2)");
          assert.strictEqual(
            description.textContent.trim(),
            "this is unsafe bookmark title <a>!",
            "the title is rendered safely as description"
          );
        },
      }
    );

    componentTest("when the bookmark reminder originates from a topic", {
      template,

      beforeEach() {
        this.set("notification", getNotification());
      },

      async test(assert) {
        const description = query("li span:nth-of-type(2)");
        assert.strictEqual(
          description.textContent.trim(),
          "This is fancy title <a>!",
          "fancy_title is safe and rendered correctly"
        );
      },
    });
  }
);
