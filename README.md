# whl-tools Collection

This repository includes the following tools:

- [Map Generation Tool](#map-generation-tool)
- [Automated Data Copy Tool](#automated-data-copy-tool)

---

## Map Generation Tool

Generate various Apollo map formats based on a given `base_map`.

### Quick Start

```bash
bash gen_all_map.sh <your_map_directory>
```

---

## Automated Data Copy Tool

Automatically copies data packages from the Apollo `data` directory to the `road_test` directory on a selected disk. After the copy process, a Feishu (Lark) notification is sent to the user.

### Quick Start

Run the following command:

```bash
bash setup_host/road_test_env.sh
```

Follow the interactive prompts:

```shell
zero@zero:~/01code/whl-tools$ bash setup_host/road_test_env.sh
Enter Apollo workspace path [/home/zero/01code/apollo]:
Enter notification Webhook URL [https://www.feishu.cn/flow/api/trigger-webhook/xxx]:
[INFO]    Available filesystems:
  1) /dev/nvme0n1p6 (UUID: f9ab690d-5e04-44d9-b9f8-c024016d8245)
  2) /dev/nvme0n1p5 (UUID: DE2411AE24118AA3)
  3) /dev/nvme0n1p3 (UUID: 560446550446386F)
  4) /dev/nvme0n1p1 (UUID: CA41-1B79)
  5) /dev/nvme0n1p4 (UUID: D62817D52817B389)
Select an entry [2]:
[INFO]    Configuration complete.
Apollo Workspace : /home/zero/01code/apollo
Webhook URL      : https://www.feishu.cn/flow/api/trigger-webhook/xxx
Disk UUID        : DE2411AE24118AA3
```

🔗 [How to Create a Feishu Webhook](https://www.feishu.cn/hc/zh-CN/articles/807992406756-webhook-%E8%A7%A6%E5%8F%91%E5%99%A8)
