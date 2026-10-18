import { useDismissFlag, useDismissSession, useShadowBan, useVoidSession } from "../api/moderation";
import { NoteModal } from "./NoteModal";

/** What the admin is about to do. The modal asks for the note and sends it. */
export type PendingAction =
  | { kind: "ban"; userId: string; name: string; banned: boolean; reviewItemId?: number }
  | { kind: "void"; sessionId: string; score: number }
  | { kind: "dismissSession"; sessionId: string }
  | { kind: "dismissFlag"; flagId: number; name: string };

/** The note dialog for one pending action; render it only while there is one. */
export function ModerationActionModal({ action, onClose }: { action: PendingAction; onClose: () => void }) {
  const ban = useShadowBan();
  const voidSession = useVoidSession();
  const dismissSession = useDismissSession();
  const dismissFlag = useDismissFlag();
  const done = { onSuccess: onClose };

  switch (action.kind) {
    case "ban":
      return (
        <NoteModal
          opened
          onClose={onClose}
          title={action.banned ? "Shadow-ban player" : "Lift shadow-ban"}
          confirmLabel={action.banned ? "Shadow-ban" : "Lift ban"}
          color={action.banned ? "red" : "blue"}
          loading={ban.isPending}
          onConfirm={(note) => ban.mutate({ userId: action.userId, banned: action.banned, note, reviewItemId: action.reviewItemId }, done)}
        >
          {action.banned
            ? `${action.name} disappears from everyone else's leaderboards (the public top 100 within a minute). They keep playing and see their own rank. Their points are kept.`
            : `${action.name} reappears on the leaderboards with the points they have.`}
        </NoteModal>
      );
    case "void":
      return (
        <NoteModal
          opened
          onClose={onClose}
          title="Void session"
          confirmLabel="Void session"
          loading={voidSession.isPending}
          onConfirm={(note) => voidSession.mutate({ sessionId: action.sessionId, note }, done)}
        >
          The session is marked void and its {action.score.toLocaleString("en-US")} points are taken off the player's leaderboards (all time, this session's week and its era). A session
          that was flagged when it was played never added points, so nothing is taken back for it.
        </NoteModal>
      );
    case "dismissSession":
      return (
        <NoteModal
          opened
          onClose={onClose}
          title="Dismiss flagged session"
          confirmLabel="Dismiss"
          color="blue"
          loading={dismissSession.isPending}
          onConfirm={(note) => dismissSession.mutate({ sessionId: action.sessionId, note }, done)}
        >
          The session leaves the queue and stays as it is: it was flagged when it was played, so its points are not on any leaderboard.
        </NoteModal>
      );
    case "dismissFlag":
      return (
        <NoteModal
          opened
          onClose={onClose}
          title="Dismiss anomaly flag"
          confirmLabel="Dismiss"
          color="blue"
          loading={dismissFlag.isPending}
          onConfirm={(note) => dismissFlag.mutate({ flagId: action.flagId, note }, done)}
        >
          {action.name} stays on the leaderboards. The nightly pass will not raise the same day again.
        </NoteModal>
      );
  }
}
