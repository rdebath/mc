using System;
using MCGalaxy;
using MCGalaxy.Events;
using MCGalaxy.Events.PlayerEvents;

// TODO: Other maps (some?) are classic not allowed.
//          OnJoiningLevelEvent.Register(Player, Level, CanJoin);
//              lvl.Config.MOTD contains +/-classic ?
//              Server.Config.MOTD contains +/-classic ?

// TODO: Save properties in file?
// TODO: Add timer; "Classic hour"

namespace Core {
    public class ClassicMode: Plugin {
        public override string MCGalaxy_Version { get { return "1.9.3.9"; } }
        public override string name { get { return "ClassicMode"; } }

        public static bool Enabled = false;
        public static string ClassicMap = "Classic";

        public override void Load(bool startup) {
            Command.Register(new CmdClassicMode());
            OnPlayerFinishConnectingEvent.Register(CheckForEnhanced, Priority.High);
            OnPlayerConnectEvent.Register(ComplainAboutClassic, Priority.Low);

            if (ClassicMap != "") {
                Level lvl = LevelActions.Load(Player.Console, ClassicMap, false);
                if (lvl == null)
                    lvl = Matcher.FindLevels(Player.Console, ClassicMap);
                if (lvl == null)
                    ClassicMap = "";
                else
                    lvl.Config.AutoUnload = false;
            }
        }

        public override void Unload(bool shutdown) {
            Command.Unregister(Command.Find("ClassicMode"));
            OnPlayerFinishConnectingEvent.Unregister(CheckForEnhanced);
            OnPlayerConnectEvent.Unregister(ComplainAboutClassic);
        }

        string IsFailed(Player p) {

            string failreason = "";
            if (!p.Session.hasCpe)
                failreason = "classic protocol extensions";
            else if (!p.Supports(CpeExt.CustomBlocks))
                failreason = "custom blocks";
            else if (!p.Supports(CpeExt.BlockDefinitions))
                failreason = "block definitions";
#if false // Beware MaxRaw is defined at compile time not load time.
            else if (Block.MaxRaw > 255 && !p.Supports(CpeExt.ExtBlocks))
                failreason = "ten bit block numbers";
#endif
            else if (!p.Supports(CpeExt.FullCP437) || !p.Supports(CpeExt.EmoteFix))
                failreason = "working chat";

            return failreason;
        }

        void ComplainAboutClassic(Player p) {
            if (Enabled) return;
            string failreason = IsFailed(p);

            if (failreason != "") {
                p.Message("You have been moved to level {1}, /main will get you to the real main level. You should connect using a client with {0} for correct operation. (e.g. ClassiCube in enhanced mode)", failreason, ClassicMap);
            }
        }

        void CheckForEnhanced(Player p) {
            if (Enabled) return;
            string failreason = IsFailed(p);

            if (failreason != "") {
                Logger.Log(LogType.UserActivity, "{0} in Classic Mode.", p.name);

                ItemPerms opchat = Chat.OpchatPerms;
                Chat.MessageFrom(p, "λNICK &Sis connecting with a classic client",
                    (pl, obj) => pl.CanSee(p) && opchat.UsableBy(pl.Rank));

                if (ClassicMap == "") {
                    p.Leave("Please use a client supporting " + failreason, true);
                    p.cancelconnecting = true;
                } else {
                    Level lvl = Matcher.FindLevels(p, ClassicMap);
                    if (lvl != null) {
                        p.level = lvl;
                    } else {
                        p.Leave("Please use a client supporting " + failreason, true);
                        p.cancelconnecting = true;
                    }
                }
            }
        }
    }

    public class CmdClassicMode : Command2 {
        public override string name { get { return "ClassicMode"; } }
        public override string shortcut { get { return "cm"; } }
        public override string type { get { return "other"; } }
        public override LevelPermission defaultRank { get { return LevelPermission.Admin; } }

        public override void Use(Player p, string message)
        {
            Player[] online = PlayerInfo.Online.Items;
            switch(message) {
            case "": ClassicMode.Enabled = !ClassicMode.Enabled; break;
            case "allow": case "enable": ClassicMode.Enabled = true; break;
            case "deny": case "disable":
                ClassicMode.Enabled = false;
                ClassicMode.ClassicMap = "";
                break;

            default:
                string[] parts = message.SplitSpaces(2);
                string NewMap = message;
                if (parts.Length == 2 && parts[0] == "map")
                    NewMap = parts[1];

                Level lvl = LevelActions.Load(p, NewMap, false);
                if (lvl == null) {
                    p.Message("Level \"{0}\" not found.", NewMap);
                    return;
                }
                lvl.Config.AutoUnload = false;
                ClassicMode.Enabled = true;
                ClassicMode.ClassicMap = NewMap;
                break;
            }

            if (ClassicMode.Enabled || ClassicMode.ClassicMap == "")
                p.Message("Classic clients are {0}", ClassicMode.Enabled?"allowed":"denied");
            else
                p.Message("Connecting classic clients are redirected to map \"{0}\"", ClassicMode.ClassicMap);
        }

        public override void Help(Player p)
        {
            p.Message("%T/ClassicMode - Allow or disallow classic clients.");
        }
    }
}
