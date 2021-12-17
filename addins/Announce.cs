using System;
using MCGalaxy;

namespace Core {
    public class Announce: Plugin {
        public override string MCGalaxy_Version { get { return "1.8.0.0"; } }
        public override string name { get { return "Announce"; } }

        public override void Load(bool startup) {
            Command.Register(new CmdAnnounce());
        }

        public override void Unload(bool shutdown) {
            Command.Unregister(Command.Find("Announce"));
        }
    }

    public class CmdAnnounce : Command2 {
        public override string name { get { return "Announce"; } }
        public override string shortcut { get { return "an"; } }
        public override string type { get { return "other"; } }
        public override LevelPermission defaultRank { get { return LevelPermission.Admin; } }

        public override void Use(Player p, string message)
        {
            Player[] online = PlayerInfo.Online.Items;

            foreach (Player pl in online) {
                pl.SendCpeMessage(CpeMessageType.Announcement, message);
            }
        }

        public override void Help(Player p)
        {
            p.Message("%T/Announce - Send really important message to everyone.");
        }
    }
}
