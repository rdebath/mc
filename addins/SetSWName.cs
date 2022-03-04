using System;
using System.IO;
using System.Text;
using MCGalaxy;

namespace Core {
    public class SetSWName : Plugin {
        public override string MCGalaxy_Version { get { return "1.8.0.0"; } }
        public override string name { get { return "SetSWName"; } }
        public static string swnamefile = "text/swname.txt";

        public override void Load(bool startup) {
            Command.Register(new CmdSetSWName());

            Server.SoftwareName = "MCGalaxy-Fork";
            try
            {
                if (File.Exists(swnamefile))
                    Server.SoftwareName = File.ReadAllText(swnamefile, Encoding.UTF8);
            }
            catch(Exception e) { }
            if (Server.SoftwareName == "")
                Server.SoftwareName = "MCGalaxy-Fork";
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
            File.WriteAllText(SetSWName.swnamefile, message, Encoding.UTF8);
        }

        public override void Help(Player p) {
            p.Message("%T/SetSWName - Set software name");
        }
    }
}
