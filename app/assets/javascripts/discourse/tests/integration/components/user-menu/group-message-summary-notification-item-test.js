import componentTest, {
  setupRenderingTest,
} from "discourse/tests/helpers/component-test";
import {
  discourseModule,
  exists,
  query,
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
        notification_type: NOTIFICATION_TYPES.group_message_summary,
        read: false,
        high_priority: false,
        created_at: "2022-07-01T06:00:32.173Z",
        data: {
          group_id: 321,
          group_name: "drummers",
          inbox_count: 13,
          username: "drummers.boss",
        },
      },
      overrides
    )
  );
}

discourseModule(
  "Integration | Component | user-menu | group-message-summary-notification-item",
  function (hooks) {
    setupRenderingTest(hooks);

    const template = hbs`<UserMenu::GroupMessageSummaryNotificationItem @item={{this.notification}}/>`;

    componentTest("the notification displays a simple i18n string", {
      template,

      beforeEach() {
        this.set("notification", getNotification());
      },

      async test(assert) {
        const notification = query("li");
        assert.strictEqual(
          notification.textContent.trim(),
          I18n.t("notifications.group_message_summary", {
            count: 13,
            group_name: "drummers",
          })
        );
        assert.ok(!exists("li span"));
      },
    });
  }
);
