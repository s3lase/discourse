import componentTest, {
  setupRenderingTest,
} from "discourse/tests/helpers/component-test";
import {
  discourseModule,
  queryAll,
} from "discourse/tests/helpers/qunit-helpers";
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
        notification_type: NOTIFICATION_TYPES.liked,
        read: false,
        high_priority: false,
        created_at: "2022-07-01T06:00:32.173Z",
        post_number: 113,
        topic_id: 449,
        fancy_title: "This is fancy title &lt;a&gt;!",
        slug: "this-is-fancy-title",
        data: {
          topic_title: "this is title before it becomes fancy <a>!",
          username: "osama",
          display_username: "osama",
          username2: "shrek",
          count: 2,
        },
      },
      overrides
    )
  );
}

discourseModule(
  "Integration | Component | user-menu | liked-notification-item",
  function (hooks) {
    setupRenderingTest(hooks);

    const template = hbs`<UserMenu::LikedNotificationItem @item={{this.notification}}/>`;

    componentTest("when the likes count is 2", {
      template,

      beforeEach() {
        this.set("notification", getNotification({ data: { count: 2 } }));
      },

      async test(assert) {
        const spans = queryAll("li span");
        assert.strictEqual(spans.length, 2);

        const label = spans[0];
        const description = spans[1];
        assert.strictEqual(
          label.textContent.trim(),
          "osama, shrek",
          "the label displays both usernames comma-concatenated"
        );
        assert.strictEqual(
          label.className,
          "double-user",
          "label has double-user class"
        );
        assert.strictEqual(
          description.textContent.trim(),
          "This is fancy title <a>!",
          "the description displays the topic title"
        );
      },
    });

    componentTest("when the likes count is more than 2", {
      template,

      beforeEach() {
        this.set("notification", getNotification({ data: { count: 3 } }));
      },

      async test(assert) {
        const spans = queryAll("li span");
        assert.strictEqual(spans.length, 2);

        const label = spans[0];
        const description = spans[1];
        assert.strictEqual(
          label.textContent.trim(),
          I18n.t("notifications.liked_by_multiple_users", {
            username: "osama",
            username2: "shrek",
            count: 1,
          }),
          "the label displays the first 2 usernames comma-concatenated with the count of remaining users"
        );
        assert.strictEqual(
          label.className,
          "multi-user",
          "label has multi-user class"
        );
        assert.strictEqual(
          description.textContent.trim(),
          "This is fancy title <a>!",
          "the description displays the topic title"
        );
      },
    });

    componentTest("when the likes count is 1", {
      template,

      beforeEach() {
        this.set(
          "notification",
          getNotification({ data: { count: 1, username2: null } })
        );
      },

      async test(assert) {
        const spans = queryAll("li span");
        assert.strictEqual(spans.length, 2);

        const label = spans[0];
        const description = spans[1];
        assert.strictEqual(
          label.textContent.trim(),
          "osama",
          "the label displays the username"
        );
        assert.strictEqual(
          description.textContent.trim(),
          "This is fancy title <a>!",
          "the description displays the topic title"
        );
      },
    });
  }
);
