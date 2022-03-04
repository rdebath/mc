using System;
using MCGalaxy;

namespace Core {
    public class PlugGC : Plugin {
        public override string MCGalaxy_Version { get { return "1.8.0.0"; } }
        public override string name { get { return "GC"; } }

        public override void Load(bool startup) {
            Command.Register(new CmdGC());
        }

        public override void Unload(bool shutdown) {
            Command.Unregister(Command.Find("GC"));
        }
    }

    public class CmdGC : Command2 {
        public override string name { get { return "GC"; } }
        public override string type { get { return "other"; } }
        public override LevelPermission defaultRank { get { return LevelPermission.Nobody; } }

        public override void Use(Player p, string message) {
            p.Message("Starting full GC");
            GC.Collect(2);
            p.Message("Completed full GC");
        }

        public override void Help(Player p) {
            p.Message("%T/GC - Set software name");
        }
    }
}
