#!/usr/bin/env python3
"""SP27 三路相机实时预览（OpenCV 独立窗口）。

订阅 /tidesense/left|right/image_raw 与 /down_camera/image，
分别弹出三个窗口；按 q 或 Esc 退出。

用法：
  source ~/TJ-Superpower/deploy/host/env.sh
  python3 camera_viewer.py
"""
import sys

import cv2
import numpy as np
import rclpy
from rclpy.node import Node
from sensor_msgs.msg import Image

TOPICS = {
    "left": "/tidesense/left/image_raw",
    "right": "/tidesense/right/image_raw",
    "down": "/down_camera/image",
}


class CameraViewer(Node):
    def __init__(self):
        super().__init__("sp27_camera_viewer")
        self.latest = {}
        self.count = {k: 0 for k in TOPICS}
        for name, topic in TOPICS.items():
            self.create_subscription(Image, topic, lambda m, n=name: self.on_image(m, n), 10)
            cv2.namedWindow(f"SP27 {name}", cv2.WINDOW_NORMAL)
            cv2.resizeWindow(f"SP27 {name}", 640, 400)
            cv2.moveWindow(f"SP27 {name}", 40 + 660 * list(TOPICS).index(name), 80)

    def on_image(self, msg, name):
        h, w = msg.height, msg.width
        buf = np.frombuffer(msg.data, dtype=np.uint8)
        if msg.encoding in ("mono8", "8UC1"):
            img = buf.reshape(h, w)
        elif msg.encoding == "rgb8":
            img = buf.reshape(h, w, 3)[:, :, ::-1]
        else:
            img = buf.reshape(h, w, 3)
        self.latest[name] = img
        self.count[name] += 1


def main():
    rclpy.init()
    node = CameraViewer()
    try:
        while rclpy.ok():
            rclpy.spin_once(node, timeout_sec=0.02)
            for name in TOPICS:
                img = node.latest.get(name)
                if img is None:
                    continue
                if img.ndim == 2:
                    shown = cv2.cvtColor(img, cv2.COLOR_GRAY2BGR)
                else:
                    shown = img.copy()
                shown = np.ascontiguousarray(shown)
                cv2.putText(shown, f"{name}  frames={node.count[name]}",
                            (8, 22), cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 255, 0), 1, cv2.LINE_AA)
                cv2.imshow(f"SP27 {name}", shown)
            key = cv2.waitKey(1) & 0xFF
            if key in (27, ord("q")):
                break
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()
        cv2.destroyAllWindows()


if __name__ == "__main__":
    sys.exit(main())
