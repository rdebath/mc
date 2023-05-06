using System;
using MCGalaxy.Events;
using MCGalaxy.Events.PlayerEvents;

namespace MCGalaxy {

    public class MotdPlugin : Plugin {
        public override string creator { get { return "Not UnknownShadow200"; } }
        public override string MCGalaxy_Version { get { return "1.9.1.4"; } }
        public override string name { get { return "MotdPlugin"; } }

        public override void Load(bool startup) {
            OnJoinedLevelEvent.Register(DoOnJoinedLevelEvent, Priority.Low);
        }

        public override void Unload(bool shutdown) {
            OnJoinedLevelEvent.Unregister(DoOnJoinedLevelEvent);
        }

        void DoOnJoinedLevelEvent(Player p, Level prevLevel, Level level, ref bool announce) {
            if (level.Config.MOTD == "ignore") return;
            string MOTD = level.Config.MOTD;
            int i = MOTD.IndexOf("&0");
            if (i < 0) i = MOTD.IndexOf("%0");
            if (i < 0) i = MOTD.IndexOf("-hax"); // Let's guess this.
            if (i == 0) return;
            if (i > 0) MOTD = MOTD.Substring(0, i);
            MOTD = MOTD.Trim();
            if (MOTD == "") return;
            p.SendCpeMessage(CpeMessageType.Announcement, MOTD);
        }
    }
}
