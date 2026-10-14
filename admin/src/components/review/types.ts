import type { TrackDetail } from "../../api/catalog";
import type { ReviewRow } from "../../api/review";

/** What every resolution panel gets: the item, whether the viewer may merge artists, and a way to say it is closed. */
export interface PanelProps {
  item: ReviewRow;
  isAdmin: boolean;
  /**
   * Call once the item has been resolved or dismissed, so the queue can move on. Pass the track's detail when the
   * server sent it back after the item was closed, so the page need not fetch it again.
   */
  onClosed: (item: ReviewRow, detail?: TrackDetail) => void;
}
