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
        notification_type: NOTIFICATION_TYPES.liked_consolidated,
        read: false,
        high_priority: false,
        created_at: "2022-07-01T06:00:32.173Z",
        data: {
          topic_title: "this is some topic and it's irrelevant",
          original_post_id: 3294,
          original_post_type: 1,
          original_username: "liker439",
          display_username: "liker439",
          username: "liker439",
          count: 44,
        },
      },
      overrides
    )
  );
}

discourseModule(
  "Integration | Component | user-menu | liked-consolidated-notification-item",
  function (hooks) {
    setupRenderingTest(hooks);

    const template = hbs`<UserMenu::LikedConsolidatedNotificationItem @item={{this.notification}}/>`;

    componentTest(
      "the notification links to the likes received notifications page of the user",
      {
        template,

        beforeEach() {
          this.set("notification", getNotification());
        },

        async test(assert) {
          const link = query("li a");
          assert.ok(
            link.href.endsWith(
              "/u/eviltrout/notifications/likes-received?acting_username=liker439"
            )
          );
        },
      }
    );

    componentTest("the notification label displays the user who liked", {
      template,

      beforeEach() {
        this.set("notification", getNotification());
      },

      async test(assert) {
        const label = query("li span");
        assert.strictEqual(label.textContent.trim(), "liker439");
      },
    });

    componentTest("the notification description displays the number of likes", {
      template,

      beforeEach() {
        this.set("notification", getNotification());
      },

      async test(assert) {
        const description = query("li span:nth-of-type(2)");
        assert.strictEqual(
          description.textContent.trim(),
          I18n.t("notifications.liked_consolidated_description", { count: 44 })
        );
      },
    });
  }
);
