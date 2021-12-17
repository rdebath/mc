using System;
using MCGalaxy;

// TODO: Save last setting to file.

namespace Core {
    public class SetSWName : Plugin {
        public override string MCGalaxy_Version { get { return "1.8.0.0"; } }
        public override string name { get { return "SetSWName"; } }

        public override void Load(bool startup) {
            Command.Register(new CmdSetSWName());
            Server.SoftwareName = "MCClone";
        }

        public override void Unload(bool shutdown) {
            Command.Unregister(Command.Find("SetSWName"));
        }
    }

    public class CmdSetSWName : Command2 {
        public override string name { get { return "SetSWName"; } }
        public override string type { get { return "other"; } }
        public override LevelPermission defaultRank { get { return LevelPermission.Nobody; } }

        public override void Use(Player p, string message) {
            Server.SoftwareName = message;
        }

        public override void Help(Player p) {
            p.Message("%T/SetSWName - Set software name");
        }
    }
}
