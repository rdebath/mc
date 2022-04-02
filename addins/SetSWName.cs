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

            try
            {
                if (File.Exists(swnamefile)) {
                    string[] lines =
                        File.ReadAllLines(swnamefile, Encoding.UTF8);
                    if (lines.Length > 0)
                        Server.SoftwareNameVersioned = lines[0];
                }
            }
            catch(Exception e) { }
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
            message = message.Replace("%", "&");
            Server.SoftwareNameVersioned = message;
            File.WriteAllText(SetSWName.swnamefile, message, Encoding.UTF8);
        }

        public override void Help(Player p) {
            p.Message("%T/SetSWName - Set full software name");
        }
    }
}
