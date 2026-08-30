import sys
import glob
import time

import numpy as np
import open3d as o3d


# ============================================================
# 配置
# ============================================================

if len(sys.argv) != 2:
    print("Usage:")
    print("  python3 test.py <pcd_directory>")
    print()
    print("Example:")
    print("  python3 test.py ./semantic_sensor_rgb_pair_pcd")
    sys.exit(1)


PCD_DIR = sys.argv[1]


# ============================================================
# RangeRet / SemanticKITTI
#
# label 是 RangeRet 的 learning class:
#
# 0  unlabeled
# 1  car
# 2  bicycle
# 3  motorcycle
# 4  truck
# 5  other-vehicle
# 6  person
# 7  bicyclist
# 8  motorcyclist
# 9  road
# 10 parking
# 11 sidewalk
# 12 other-ground
# 13 building
# 14 fence
# 15 vegetation
# 16 trunk
# 17 terrain
# 18 pole
# 19 traffic-sign
#
# 对应 SemanticKITTI learning_map_inv:
#
# 0  -> 0
# 1  -> 10
# 2  -> 11
# 3  -> 15
# 4  -> 18
# 5  -> 20
# 6  -> 30
# 7  -> 31
# 8  -> 32
# 9  -> 40
# 10 -> 44
# 11 -> 48
# 12 -> 49
# 13 -> 50
# 14 -> 51
# 15 -> 70
# 16 -> 71
# 17 -> 72
# 18 -> 80
# 19 -> 81
# ============================================================


LABEL_NAMES = {
    0: "unlabeled",
    1: "car",
    2: "bicycle",
    3: "motorcycle",
    4: "truck",
    5: "other-vehicle",
    6: "person",
    7: "bicyclist",
    8: "motorcyclist",
    9: "road",
    10: "parking",
    11: "sidewalk",
    12: "other-ground",
    13: "building",
    14: "fence",
    15: "vegetation",
    16: "trunk",
    17: "terrain",
    18: "pole",
    19: "traffic-sign",
}


# ============================================================
# SemanticKITTI 官方 color_map
#
# 官方配置是 BGR。
# 这里转换成 RGB 给 Open3D 使用。
#
# 原始 BGR:
#
# 0  : [0, 0, 0]
# 10 : [245, 150, 100]   car
# 11 : [245, 230, 100]   bicycle
# 15 : [150, 60, 30]     motorcycle
# 18 : [180, 30, 80]     truck
# 20 : [255, 0, 0]       other-vehicle
# 30 : [30, 30, 255]     person
# 31 : [200, 40, 255]    bicyclist
# 32 : [90, 30, 150]     motorcyclist
# 40 : [255, 0, 255]     road
# 44 : [255, 150, 255]   parking
# 48 : [75, 0, 75]       sidewalk
# 49 : [75, 0, 175]      other-ground
# 50 : [0, 200, 255]     building
# 51 : [50, 120, 255]    fence
# 70 : [0, 175, 0]       vegetation
# 71 : [0, 60, 135]      trunk
# 72 : [80, 240, 150]    terrain
# 80 : [150, 240, 255]   pole
# 81 : [0, 0, 255]       traffic-sign
#
# BGR -> RGB
# ============================================================


LABEL_COLORS = {
    0:  [0.0,   0.0,   0.0],       # unlabeled

    1:  [100/255, 150/255, 245/255],   # car
    2:  [100/255, 230/255, 245/255],   # bicycle
    3:  [30/255, 60/255, 150/255],     # motorcycle
    4:  [80/255, 30/255, 180/255],     # truck
    5:  [0.0,   0.0,   1.0],           # other-vehicle
    6:  [1.0,   30/255, 30/255],       # person
    7:  [1.0,   40/255, 200/255],      # bicyclist
    8:  [150/255, 30/255, 90/255],     # motorcyclist

    9:  [1.0,   0.0,   1.0],           # road
    10: [1.0,   150/255, 1.0],         # parking
    11: [75/255, 0.0,   75/255],       # sidewalk
    12: [175/255, 0.0,  75/255],       # other-ground
    13: [1.0,   200/255, 0.0],         # building
    14: [1.0,   120/255, 50/255],      # fence

    15: [0.0,   175/255, 0.0],         # vegetation
    16: [135/255, 60/255, 0.0],        # trunk
    17: [150/255, 240/255, 80/255],    # terrain
    18: [255/255, 240/255, 150/255],   # pole
    19: [1.0,   0.0,   0.0],           # traffic-sign
}


DEFAULT_COLOR = [0.5, 0.5, 0.5]


# ============================================================
# 找到 PCD
# ============================================================

pcd_files = sorted(
    glob.glob(f"{PCD_DIR}/*.pcd")
)

if not pcd_files:
    raise RuntimeError(
        f"目录中没有找到 PCD 文件: {PCD_DIR}"
    )

print(f"Found {len(pcd_files)} PCD files")


# ============================================================
# 读取 PCD
# ============================================================

def load_pcd(filename):

    # --------------------------------------------------------
    # Open3D 读取 XYZ
    # --------------------------------------------------------

    pcd = o3d.io.read_point_cloud(filename)

    if len(pcd.points) == 0:
        raise RuntimeError(
            f"无法读取点云或点云为空: {filename}"
        )

    # --------------------------------------------------------
    # 读取 ASCII 数据
    # --------------------------------------------------------

    with open(filename, "r") as f:
        lines = f.readlines()

    data_start = next(
        (
            i + 1
            for i, line in enumerate(lines)
            if line.strip().lower() == "data ascii"
        ),
        None,
    )

    if data_start is None:
        raise RuntimeError(
            f"PCD 中未找到 DATA ascii: {filename}"
        )

    data = np.loadtxt(
        lines[data_start:],
        dtype=np.float32,
    )

    if data.ndim == 1:
        data = data.reshape(1, -1)

    if data.shape[1] < 5:
        raise RuntimeError(
            f"PCD 字段不足，至少需要:"
            f" x y z intensity label"
        )

    # --------------------------------------------------------
    # 检查点数
    # --------------------------------------------------------

    if len(pcd.points) != len(data):
        raise RuntimeError(
            f"点数不一致:\n"
            f"  Open3D = {len(pcd.points)}\n"
            f"  ASCII  = {len(data)}"
        )

    # --------------------------------------------------------
    # fields
    # --------------------------------------------------------

    intensity = data[:, 3]

    labels = data[:, 4].astype(
        np.int32
    )

    if data.shape[1] >= 6:
        confidence = data[:, 5]
    else:
        confidence = np.ones(
            len(data),
            dtype=np.float32,
        )

    return (
        pcd,
        intensity,
        labels,
        confidence,
    )


# ============================================================
# Label -> RGB
# ============================================================

def label_to_colors(labels):

    colors = np.empty(
        (len(labels), 3),
        dtype=np.float64,
    )

    colors[:] = DEFAULT_COLOR

    for label_id, color in LABEL_COLORS.items():

        mask = labels == label_id

        colors[mask] = color

    return colors


# ============================================================
# Intensity -> RGB
# ============================================================

def intensity_to_colors(intensity):

    if len(intensity) == 0:
        return np.empty(
            (0, 3),
            dtype=np.float64,
        )

    low = np.percentile(
        intensity,
        1,
    )

    high = np.percentile(
        intensity,
        99,
    )

    if high > low:

        normalized = (
            intensity - low
        ) / (
            high - low
        )

    else:

        normalized = np.zeros_like(
            intensity
        )

    normalized = np.clip(
        normalized,
        0.0,
        1.0,
    )

    return np.stack(
        [
            normalized,
            normalized,
            normalized,
        ],
        axis=1,
    ).astype(np.float64)


# ============================================================
# Confidence -> RGB
# ============================================================

def confidence_to_colors(confidence):

    confidence = np.clip(
        confidence,
        0.0,
        1.0,
    )

    # 低 confidence -> 蓝色
    # 中间 -> 绿色
    # 高 confidence -> 红色

    r = confidence

    g = 1.0 - np.abs(
        confidence - 0.5
    ) * 2.0

    b = 1.0 - confidence

    colors = np.stack(
        [
            r,
            g,
            b,
        ],
        axis=1,
    )

    return colors.astype(
        np.float64
    )


# ============================================================
# Viewer
# ============================================================

class Viewer:

    def __init__(self, files):

        self.files = files

        self.index = 0

        self.mode = "label"

        self.playing = False

        self.point_size = 2.0

        self.pcd = None

        self.intensity = None

        self.labels = None

        self.confidence = None

        self.vis = (
            o3d.visualization
            .VisualizerWithKeyCallback()
        )

        self.vis.create_window(
            window_name="RangeRet SemanticKITTI Viewer",
            width=1280,
            height=720,
        )

        # ----------------------------------------------------
        # Keyboard
        # ----------------------------------------------------

        self.vis.register_key_callback(
            263,  # Left
            self.previous_frame,
        )

        self.vis.register_key_callback(
            262,  # Right
            self.next_frame,
        )

        self.vis.register_key_callback(
            32,   # Space
            self.toggle_play,
        )

        self.vis.register_key_callback(
            ord("1"),
            self.mode_label,
        )

        self.vis.register_key_callback(
            ord("2"),
            self.mode_intensity,
        )

        self.vis.register_key_callback(
            ord("3"),
            self.mode_confidence,
        )

        self.vis.register_key_callback(
            ord("R"),
            self.reset_view,
        )

        self.vis.register_key_callback(
            ord("+"),
            self.increase_point_size,
        )

        self.vis.register_key_callback(
            ord("-"),
            self.decrease_point_size,
        )

        # ----------------------------------------------------
        # Load first
        # ----------------------------------------------------

        self.load_frame(0)


    # ========================================================
    # Load Frame
    # ========================================================

    def load_frame(self, index):

        index = max(
            0,
            min(
                index,
                len(self.files) - 1,
            ),
        )

        self.index = index

        filename = self.files[index]

        print()
        print("=" * 80)

        print(
            f"[{index + 1}/{len(self.files)}] "
            f"{filename}"
        )

        start = time.time()

        (
            pcd,
            intensity,
            labels,
            confidence,
        ) = load_pcd(filename)

        elapsed = (
            time.time() - start
        )

        self.pcd = pcd

        self.intensity = intensity

        self.labels = labels

        self.confidence = confidence

        # ----------------------------------------------------
        # 设置颜色
        # ----------------------------------------------------

        self.update_colors()

        # ----------------------------------------------------
        # Geometry
        # ----------------------------------------------------

        self.vis.clear_geometries()

        self.vis.add_geometry(
            self.pcd
        )

        # ----------------------------------------------------
        # Render
        # ----------------------------------------------------

        render = (
            self.vis.get_render_option()
        )

        render.point_size = (
            self.point_size
        )

        # ----------------------------------------------------
        # Frame 信息
        # ----------------------------------------------------

        unique_labels, counts = (
            np.unique(
                labels,
                return_counts=True,
            )
        )

        print(
            f"points     : {len(labels)}"
        )

        print(
            f"load time  : {elapsed:.3f}s"
        )

        print(
            f"color mode : {self.mode}"
        )

        print(
            "labels:"
        )

        for label_id, count in zip(
            unique_labels,
            counts,
        ):

            name = LABEL_NAMES.get(
                int(label_id),
                "UNKNOWN",
            )

            percentage = (
                count
                / len(labels)
                * 100.0
            )

            print(
                f"  {int(label_id):2d} "
                f"{name:15s} "
                f"{count:7d} "
                f"({percentage:6.2f}%)"
            )

        print()
        print(
            "Controls:"
        )

        print(
            "  ← / →     Previous / Next frame"
        )

        print(
            "  Space     Play / Pause"
        )

        print(
            "  1         Label"
        )

        print(
            "  2         Intensity"
        )

        print(
            "  3         Confidence"
        )

        print(
            "  R         Reset view"
        )

        print(
            "  + / -     Point size"
        )


    # ========================================================
    # Color
    # ========================================================

    def update_colors(self):

        if self.mode == "label":

            colors = (
                label_to_colors(
                    self.labels
                )
            )

        elif self.mode == "intensity":

            colors = (
                intensity_to_colors(
                    self.intensity
                )
            )

        elif self.mode == "confidence":

            colors = (
                confidence_to_colors(
                    self.confidence
                )
            )

        else:

            colors = (
                label_to_colors(
                    self.labels
                )
            )

        self.pcd.colors = (
            o3d.utility.Vector3dVector(
                colors
            )
        )

        self.vis.update_geometry(
            self.pcd
        )


    # ========================================================
    # Modes
    # ========================================================

    def mode_label(self, vis):

        self.mode = "label"

        print(
            "Color mode: LABEL"
        )

        self.update_colors()


    def mode_intensity(self, vis):

        self.mode = "intensity"

        print(
            "Color mode: INTENSITY"
        )

        self.update_colors()


    def mode_confidence(self, vis):

        self.mode = "confidence"

        print(
            "Color mode: CONFIDENCE"
        )

        self.update_colors()


    # ========================================================
    # Frame navigation
    # ========================================================

    def next_frame(self, vis):

        if self.index + 1 < len(
            self.files
        ):

            self.load_frame(
                self.index + 1
            )


    def previous_frame(self, vis):

        if self.index > 0:

            self.load_frame(
                self.index - 1
            )


    # ========================================================
    # Play
    # ========================================================

    def toggle_play(self, vis):

        self.playing = (
            not self.playing
        )

        print(
            "PLAY"
            if self.playing
            else "PAUSE"
        )


    # ========================================================
    # Reset
    # ========================================================

    def reset_view(self, vis):

        self.vis.reset_view_point(
            True
        )

        print(
            "View reset"
        )


    # ========================================================
    # Point Size
    # ========================================================

    def increase_point_size(self, vis):

        self.point_size += 0.5

        self.point_size = min(
            self.point_size,
            10.0,
        )

        render = (
            self.vis.get_render_option()
        )

        render.point_size = (
            self.point_size
        )

        print(
            f"Point size: "
            f"{self.point_size}"
        )


    def decrease_point_size(self, vis):

        self.point_size -= 0.5

        self.point_size = max(
            self.point_size,
            1.0,
        )

        render = (
            self.vis.get_render_option()
        )

        render.point_size = (
            self.point_size
        )

        print(
            f"Point size: "
            f"{self.point_size}"
        )


    # ========================================================
    # Run
    # ========================================================

    def run(self):

        last_play_time = time.time()

        while True:

            if not self.vis.poll_events():
                break

            self.vis.update_renderer()

            # ------------------------------------------------
            # Playback
            # ------------------------------------------------

            if self.playing:

                now = time.time()

                if (
                    now - last_play_time
                    >= 0.1
                ):

                    last_play_time = now

                    if (
                        self.index + 1
                        < len(self.files)
                    ):

                        self.load_frame(
                            self.index + 1
                        )

                    else:

                        self.playing = False

            time.sleep(
                0.005
            )

        self.vis.destroy_window()


# ============================================================
# Main
# ============================================================

if __name__ == "__main__":

    viewer = Viewer(
        pcd_files
    )

    viewer.run()
