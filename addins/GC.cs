using System;
using MCGalaxy;
using MCGalaxy.Events.PlayerEvents;

namespace Core {
    public class PlugGC : Plugin {
        public override string MCGalaxy_Version { get { return "1.8.0.0"; } }
        public override string name { get { return "GC"; } }

        public override void Load(bool startup) {
            Command.Register(new CmdGC());
            // OnPlayerDisconnectEvent.Register(GCLogoff, Priority.Low);
        }

        public override void Unload(bool shutdown) {
            Command.Unregister(Command.Find("GC"));
            // OnPlayerDisconnectEvent.Unregister(GCLogoff);
        }

        void GCLogoff(Player p, string discmsg) {
            Server.DoGC();
        }
    }

    public class CmdGC : Command2 {
        public override string name { get { return "GC"; } }
        public override string type { get { return "other"; } }
        public override LevelPermission defaultRank { get { return LevelPermission.Nobody; } }

        public override void Use(Player p, string message) {
            GC.Collect(); // Blocking collection of all memory
            GC.WaitForPendingFinalizers();
            p.Message("Completed full GC");
        }

        public override void Help(Player p) {
            p.Message("%T/GC - Run a DotNET garbage collection cycle");
        }
    }
}
