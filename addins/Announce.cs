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

            foreach (Player target in online) {
                if (Chat.Ignoring(target, p)) continue;
                string[] parts = message.Split('|');
                string Announcement = parts[0];
                string SmallAnno = "&8from " +  p.FormatNick(p);
                string BigAnno = "";
                if (parts.Length > 1) SmallAnno = parts[1];
                if (parts.Length > 2) BigAnno = parts[2];

                if (Announcement != "")
                    target.SendCpeMessage(CpeMessageType.Announcement, Announcement);
                if (SmallAnno != "")
                    target.SendCpeMessage(CpeMessageType.SmallAnnouncement, SmallAnno);
                if (BigAnno != "")
                    target.SendCpeMessage(CpeMessageType.BigAnnouncement, BigAnno);
            }
        }

        public override void Help(Player p)
        {
            p.Message("%T/Announce - Send really important message to everyone.");
        }
    }
}
