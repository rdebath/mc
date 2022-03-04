using System;
using MCGalaxy.Events;
using MCGalaxy.Events.PlayerEvents;
using BlockID = System.UInt16;

// First part of routine to disable the placing of flooding blocks.
// TODO: /place, draw commands etc.

namespace MCGalaxy {

    public class DisableWaterPlugin : Plugin {
        public override string creator { get { return "Not UnknownShadow200"; } }
        public override string MCGalaxy_Version { get { return "1.9.1.4"; } }
        public override string name { get { return "DisableWaterPlugin"; } }

        public override void Load(bool startup) {
            OnBlockChangingEvent.Register(CancelWaterBlock, Priority.Low);
        }

        public override void Unload(bool shutdown) {
            OnBlockChangingEvent.Unregister(CancelWaterBlock);
        }

        void CancelWaterBlock(Player p, ushort x, ushort y, ushort z, BlockID block, bool placing, ref bool cancel) {

            if (!placing) return;
            if (block == Block.Water || block == Block.Lava) {
                cancel = true;
                p.RevertBlock(x, y, z);
            }

        }

    }
}
