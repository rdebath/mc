using System;
using MCGalaxy;
using MCGalaxy.Events;
using MCGalaxy.Events.PlayerEvents;
using MCGalaxy.Blocks;
using MCGalaxy.Network;


namespace Core {
    public class ClearHotBar: Plugin {
        public override string MCGalaxy_Version { get { return "1.9.3.9"; } }
        public override string name { get { return "ClearHotBar"; } }

        public override void Load(bool startup) {
            Command.Register(new CmdClearHotBar());
            OnPlayerConnectEvent.Register(RunLogonTask, Priority.Low);
            OnJoinedLevelEvent.Register(DoLevelHotbarClear, Priority.Low);
        }

        public override void Unload(bool shutdown) {
            Command.Unregister(Command.Find("ClearHotBar"));
            OnPlayerConnectEvent.Unregister(RunLogonTask);
            OnJoinedLevelEvent.Unregister(DoLevelHotbarClear);
        }

        void RunLogonTask(Player p) {
            // ClearHotbar(p);
        }

        void DoLevelHotbarClear(Player p, Level prevLevel, Level level, ref bool announce) {
            if (!level.Config.MOTD.Contains("+chb"))
                return;
            ClearHotbar(p);
        }

        public static void ClearHotbar(Player p) {
            if (!p.Session.hasCpe || !p.Supports(CpeExt.SetHotbar)) return;

            for (byte i = 0; i <= 9; i++) {
                p.Send(Packet.SetHotbar(0, i, p.Session.hasExtBlocks));
            }
        }
    }

    public class CmdClearHotBar : Command2 {
        public override string name { get { return "ClearHotBar"; } }
        public override string shortcut { get { return "chb"; } }
        public override string type { get { return "other"; } }
        public override LevelPermission defaultRank { get { return LevelPermission.Guest; } }

        public override void Use(Player p, string message)
        {
            ClearHotBar.ClearHotbar(p);
        }

        public override void Help(Player p)
        {
            p.Message("%T/ClearHotBar - Clear the Hotbar");
        }
    }
}
