#!/usr/bin/env python3
"""
Vá tĩnh hook vào UnityFramework (không vá code lúc chạy — bản ký Ksign có
CS_HARD|CS_KILL, kernel giết nếu trang code bị sửa sau khi ký).

Cơ chế:
  - Thêm segment __CTHOOK (RW) chứa N slot 8 byte.
  - Mỗi hàm đích bị ghi 12 byte ở entry:
        adrp x16, slot@PAGE
        ldr  x16, [x16, slot@PAGEOFF]
        br   x16
  - Dylib lúc nạp ghi vào slot địa chỉ trampoline (chạy lại 3 lệnh gốc rồi
    nhảy về func+12) => hành vi y như cũ; khi bật tính năng thì ghi địa chỉ
    hàm hook vào slot.
  - Trampoline nằm trong dylib, chứa nguyên 3 lệnh gốc (đã kiểm tra không
    PC-relative) + nhảy qua con trỏ trong __DATA của dylib.

Lệnh:
  make_static_hooks.py generate <UnityFramework> <dump.cs> <gen_dir>
  make_static_hooks.py patch    <UnityFramework> <gen_dir>
"""
import json
import os
import re
import struct
import sys

from capstone import Cs, CS_ARCH_ARM64, CS_MODE_ARM

# key, class, method, paramCount
TARGETS = [
    ("dmg",       "NumericSkillManager",      "GetBaseDmgWith_CritAndBlk", 6),
    ("crit",      "NumericSkillManager",      "IsCritial",                 1),
    ("inval",     "NumericSkillManager",      "CheckDmgIsInvalid",         1),
    ("cd",        "NumericActor",             "GetSkillCDTime",            1),
    ("mana",      "NumericBattleCenter",      "GetMana",                   1),
    ("win",       "NumericCalculate",         "IsWin",                     0),
    ("hp",        "BattleFormula",            "Get_Final_HP",              1),
    ("lock2",     "SecretModule",             "IsLockByRoleFavorite",      2),
    ("lock3",     "SecretModule",             "IsLockByRoleFavorite",      3),
    ("puzlv",     "RolePuzzleData",           "get_GetOpenLv",             0),
    ("seclv",     "RoleSecretSetionData",     "get_GetOpenLv",             0),
    ("favexp",    "RoleFavorability",         "get_Exp",                   0),
    ("favlvl",    "RoleFavorability",         "get_Level",                 0),
    ("excited",   "SecretHCGClickGameMainUI", "AddExcited",                1),
    ("skipbattle","BattleCenter",             "IsSkipBattle",              0),
    ("autofight", "StageModule",              "get_IsNeedAutoFight",       0),
    ("autofighting","UIPreferecneModule",     "get_AutoFighting",          0),
    ("teaching",  "TeachingModule",           "isTeachingID_CanBeTrigger", 1),
    ("hcgcomplete","SecretModule.HCG",        "IsComplete",                0),
    ("favlvmain",  "RoleMain",                "get_FavLv",                 0),
    ("odmg",       "ActorController",         "GetBaseDmgWith_CritAndBlk", 6),
    ("ocrit",      "SkillEffectManager",      "IsCritial",                 1),
    ("ocd",        "Actor",                   "GetSkillCDTime",            1),
    ("storytag",   "StageModule",             "IsStoryBookTagOpen",        1),
    ("storymem",   "StageModule",             "IsStoryBookMemoryAreaOpen", 1),
    ("oinval",     "ActorController",         "CheckDmgIsInvalid",         1),
    ("omana",      "ActorController",         "GetNowMana",                1),
    ("owin",       "ActorController",         "isEnemyAllDead",            0),
    ("onotenough", "ActorController",         "IsNotEnough1Mana",          1),
    ("ostep1",     "ActorController",         "IsEnough1StepMana",         1),
    ("ostep2",     "ActorController",         "IsEnough2StepMana",         1),
    ("starcond",   "BattleResultModule",      "IsMatchStarCondition",      2),
    ("ad_tapdb_start",  "TapDB",              "onStart",                   3),
    ("ad_tapdb_event",  "TapDB",              "onEvent",                   2),
    ("ad_adjust_start", "AdjustManager",      "StartAdjust",               0),
    ("ad_adjust_event", "AdjustManager",      "TrackEvent",                1),
    ("ad_adjust_buy",   "AdjustManager",      "TrackPurchase",             2),
]

# Target chỉ bật khi build với CT_WITH_CLICK=1: hook OnPointerClick của nút game để
# engine autoclick biết "click thật". Chỉ dùng khi cần recon lại toạ độ.
CLICK_TARGETS = [
    ("click_btnev", "BtnClickEvent", "OnPointerClick", 1),
]

def get_targets():
    if os.environ.get("CT_WITH_CLICK") == "1":
        return TARGETS + CLICK_TARGETS
    return TARGETS


PAGE = 0x4000
SLOT_SEG = "__CTHOOK"
SLOT_SEC = "__ctslots"

md = Cs(CS_ARCH_ARM64, CS_MODE_ARM)
PCREL = {"adr", "adrp", "b", "bl", "cbz", "cbnz", "tbz", "tbnz"}


def count_params(s):
    s = s.strip()
    if not s:
        return 0
    depth = 0
    n = 1
    for ch in s:
        if ch in "<([":
            depth += 1
        elif ch in ">)]":
            depth = max(0, depth - 1)
        elif ch == "," and depth == 0:
            n += 1
    return n


def parse_dump(dump_path):
    lines = open(dump_path, encoding="utf-8", errors="replace").read().split("\n")
    blocks, cur = [], None
    for i, l in enumerate(lines):
        m = re.match(r'^(?:public|internal|private|protected)?\s*'
                     r'(?:static\s+|sealed\s+|abstract\s+|partial\s+)*'
                     r'(class|struct|enum)\s+([^\s:<{]+)', l)
        if m and not l.strip().startswith("//"):
            cur = {"name": m.group(2), "start": i, "end": len(lines)}
            blocks.append(cur)
    for a, b in zip(blocks, blocks[1:]):
        a["end"] = b["start"]

    def find(cls, meth, pc):
        for b in blocks:
            if b["name"] != cls:
                continue
            rva = None
            for i in range(b["start"], b["end"]):
                l = lines[i]
                m = re.match(r'\s*// RVA: 0x([0-9A-Fa-f]+)', l)
                if m:
                    rva = int(m.group(1), 16)
                if re.search(r'\b' + re.escape(meth) + r'\s*\(', l) and not l.strip().startswith("//"):
                    params = l[l.find("(") + 1:l.rfind(")")]
                    n = count_params(params)
                    if n == pc and rva is not None:
                        return rva
        return None

    out = {}
    for key, cls, meth, pc in get_targets():
        rva = find(cls, meth, pc)
        if rva is None:
            raise SystemExit(f"không tìm thấy RVA cho {cls}.{meth}/{pc}")
        out[key] = rva
    return out


def encode_stub(entry_va, slot_va):
    """3 lệnh: adrp x16, slot@PAGE; ldr x16,[x16,#off]; br x16"""
    assert slot_va % 8 == 0
    pc_page = entry_va & ~0xFFF
    tgt_page = slot_va & ~0xFFF
    delta = (tgt_page - pc_page) >> 12
    immlo = delta & 0x3
    immhi = (delta >> 2) & 0x7FFFF
    adrp = 0x90000000 | (immlo << 29) | (immhi << 5) | 16
    off = slot_va & 0xFFF
    assert off % 8 == 0 and off // 8 < 4096
    ldr = 0xF9400000 | ((off // 8) << 10) | (16 << 5) | 16
    br = 0xD61F0000 | (16 << 5)
    return struct.pack("<III", adrp, ldr, br)


def check_reloc(code, va):
    ins = list(md.disasm(code[:12], va))
    if len(ins) < 3:
        return False, "không đủ 3 lệnh"
    for i in ins[:3]:
        if i.mnemonic in PCREL:
            return False, f"{i.mnemonic} {i.op_str}"
        if i.mnemonic.startswith("ldr") and "pc" in i.op_str:
            return False, f"{i.mnemonic} {i.op_str}"
    return True, ""


def add_segment(uf_path):
    """Thêm segment RW chứa các slot; trả về RVA của slot đầu tiên."""
    import lief
    b = lief.MachO.parse(uf_path).at(0)
    M = lief.MachO
    last = max(b.segments, key=lambda s: s.virtual_address + s.virtual_size)
    vm = (last.virtual_address + last.virtual_size + PAGE - 1) & ~(PAGE - 1)
    fsz = os.path.getsize(uf_path)
    foff = (fsz + PAGE - 1) & ~(PAGE - 1)
    seg = M.SegmentCommand()
    seg.name = SLOT_SEG
    seg.virtual_address = vm
    seg.file_offset = foff
    seg.init_protection = 3
    seg.max_protection = 3
    sec = M.Section.create(SLOT_SEC, [0] * PAGE)
    sec.segment_name = SLOT_SEG
    sec.alignment = 3
    seg.add_section(sec)
    b.add(seg)
    b.write(uf_path)
    b2 = lief.MachO.parse(uf_path).at(0)
    s = b2.get_section(SLOT_SEC)
    return s.virtual_address


def write_gen(gen_dir, rvas, tramps, slot_rva):
    os.makedirs(gen_dir, exist_ok=True)
    T = get_targets()
    # assembly
    lines = []
    for idx, (key, _, _, _) in enumerate(T):
        w0, w1, w2 = tramps[key]
        lines += [
            '.section __TEXT,__text,regular,pure_instructions',
            '.p2align 2',
            f'.globl _ct_tramp_{idx}',
            f'_ct_tramp_{idx}:',
            f'    .long 0x{w0:08x}',
            f'    .long 0x{w1:08x}',
            f'    .long 0x{w2:08x}',
            f'    adrp x16, _ct_back_{idx}@PAGE',
            f'    ldr  x16, [x16, _ct_back_{idx}@PAGEOFF]',
            '    br   x16',
        ]
    lines += ['.section __DATA,__data']
    for idx, _ in enumerate(T):
        lines += ['.p2align 3', f'.globl _ct_back_{idx}', f'_ct_back_{idx}:', '    .quad 0']
    open(os.path.join(gen_dir, "ct_tramps.s"), "w").write("\n".join(lines) + "\n")

    # header
    h = ["// Sinh tự động bởi tools/make_static_hooks.py — đừng sửa tay.",
         "#pragma once", "#include <stdint.h>", "",
         f"#define CT_TARGET_COUNT {len(T)}"]
    for idx, (key, _, _, _) in enumerate(T):
        h.append(f"#define CT_T_{key} {idx}")
    h.append("")
    for idx, _ in enumerate(T):
        h.append(f'extern "C" void ct_tramp_{idx}(void);')
        h.append(f'extern "C" uint64_t ct_back_{idx};')
    h.append("")
    h.append("typedef struct { const char *key; const char *cls; const char *meth; int pc;")
    h.append("                 uint64_t rva; uint64_t slotRva; } CTTarget;")
    h.append("static const CTTarget CT_TARGETS[CT_TARGET_COUNT] = {")
    for idx, (key, cls, meth, pc) in enumerate(T):
        h.append(f'  {{"{key}", "{cls}", "{meth}", {pc}, 0x{rvas[key]:x}ull, 0x{slot_rva + idx*8:x}ull}},')
    h.append("};")
    h.append("#define CT_TRAMP_TABLE { " + ", ".join(f"(void*)ct_tramp_{i}" for i in range(len(T))) + " }")
    h.append("#define CT_BACK_TABLE { " + ", ".join(f"&ct_back_{i}" for i in range(len(T))) + " }")
    open(os.path.join(gen_dir, "ct_targets.h"), "w").write("\n".join(h) + "\n")

    json.dump({
        "slotRva": slot_rva,
        "targets": [
            {"key": k, "rva": rvas[k], "slotRva": slot_rva + i * 8,
             "tramp": [tramps[k][0], tramps[k][1], tramps[k][2]]}
            for i, (k, _, _, _) in enumerate(T)
        ],
    }, open(os.path.join(gen_dir, "ct_targets.json"), "w"), indent=1)


def generate(uf_path, dump_path, gen_dir):
    rvas = parse_dump(dump_path)
    data = open(uf_path, "rb").read()
    tramps = {}
    for key, cls, meth, pc in get_targets():
        rva = rvas[key]
        code = data[rva:rva + 12]
        ok, why = check_reloc(code, rva)
        if not ok:
            raise SystemExit(f"{cls}.{meth}: prologue không di chuyển được ({why})")
        w = struct.unpack("<III", code)
        tramps[key] = w
        print(f"  {cls}.{meth}/{pc}: RVA 0x{rva:x} OK")

    tmp = uf_path + ".gen"
    import shutil
    shutil.copyfile(uf_path, tmp)
    slot_rva = add_segment(tmp)
    os.remove(tmp)
    write_gen(gen_dir, rvas, tramps, slot_rva)
    print(f"→ slot RVA = 0x{slot_rva:x}, sinh {gen_dir}/ct_tramps.s + ct_targets.h")


def patch(uf_path, gen_dir):
    info = json.load(open(os.path.join(gen_dir, "ct_targets.json")))
    slot_rva = info["slotRva"]

    import shutil
    tmp = uf_path + ".patched"
    shutil.copyfile(uf_path, tmp)
    actual = add_segment(tmp)
    if actual != slot_rva:
        os.remove(tmp)
        raise SystemExit(f"layout slot lệch: mong {hex(slot_rva)}, được {hex(actual)}")

    # ghi stub vào từng entry (__TEXT có file offset == RVA)
    with open(tmp, "r+b") as f:
        for t in info["targets"]:
            stub = encode_stub(t["rva"], t["slotRva"])
            f.seek(t["rva"])
            f.write(stub)
    shutil.move(tmp, uf_path)
    print(f"→ đã vá {len(info['targets'])} hàm (slot @ 0x{slot_rva:x})")


def main():
    if len(sys.argv) < 4:
        raise SystemExit(__doc__)
    cmd = sys.argv[1]
    if cmd == "generate":
        generate(sys.argv[2], sys.argv[3], sys.argv[4] if len(sys.argv) > 4 else "gen")
    elif cmd == "patch":
        patch(sys.argv[2], sys.argv[3])
    else:
        raise SystemExit(__doc__)


if __name__ == "__main__":
    main()
