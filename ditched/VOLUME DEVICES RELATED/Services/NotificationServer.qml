pragma Singleton
import Quickshell
import Quickshell.Services.Notifications

NotificationServer {
    id: server
    // exposes server.trackedNotifications as a model you bind a Repeater to

    onNotification: (notification) => {
        console.log("RAW BODY:", JSON.stringify(notification.body))
    }
}
