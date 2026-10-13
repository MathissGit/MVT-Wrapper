#!/usr/bin/env python3
"""Informations d'appareil (iOS / Android) pour le wrapper MVT.

Lit les sources produites par MVT et AndroidQF et imprime des lignes
"champ<TAB>valeur" dans un ordre d'affichage stable. Aucune dépendance
externe : le wrapper formate ensuite ces lignes pour le rapport.

Usage : python3 deviceinfo.py <dossier> [Cle=Valeur ...]
  Cle=Valeur surcharge une valeur (ex. IMEI=..., Serial=...).
"""
import base64
import json
import os
import plistlib
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from jsonutils import search


# Ordre d'affichage dans le rapport (libellés sans accent, historiques).
ORDER = [
    "Nom de l'appareil", "Marque", "Modele", "Systeme d exploitation",
    "Build", "Dernier patch de securite", "Numero de telephone", "IMEI",
    "Numero de serie", "ICCID", "MEID", "Target identifier",
    "Derniere sauvegarde", "Applications installees", "Capacite stockage",
]

# Libellé rapport -> nom de la surcharge acceptée en ligne de commande.
OVERRIDE = {
    "Nom de l'appareil": "DeviceName", "Marque": "Brand", "Modele": "Model",
    "Systeme d exploitation": "OS", "Build": "Build", "IMEI": "IMEI",
    "Numero de serie": "Serial", "Capacite stockage": "Storage",
    "Numero de telephone": "Phone",
}

APPLE_MODELS = {
    "iPhone1,1": "iPhone (1re)", "iPhone1,2": "iPhone 3G", "iPhone2,1": "iPhone 3GS",
    "iPhone3,1": "iPhone 4", "iPhone3,3": "iPhone 4 (CDMA)",
    "iPhone4,1": "iPhone 4s", "iPhone5,1": "iPhone 5", "iPhone5,2": "iPhone 5",
    "iPhone5,3": "iPhone 5c", "iPhone5,4": "iPhone 5c",
    "iPhone6,1": "iPhone 5s", "iPhone6,2": "iPhone 5s",
    "iPhone7,1": "iPhone 6 Plus", "iPhone7,2": "iPhone 6",
    "iPhone8,1": "iPhone 6s", "iPhone8,2": "iPhone 6s Plus", "iPhone8,4": "iPhone SE (1re gen.)",
    "iPhone9,1": "iPhone 7", "iPhone9,2": "iPhone 7 Plus",
    "iPhone9,3": "iPhone 7", "iPhone9,4": "iPhone 7 Plus",
    "iPhone10,1": "iPhone 8", "iPhone10,2": "iPhone 8 Plus", "iPhone10,3": "iPhone X",
    "iPhone10,4": "iPhone 8", "iPhone10,5": "iPhone 8 Plus", "iPhone10,6": "iPhone X",
    "iPhone11,2": "iPhone XS", "iPhone11,4": "iPhone XS Max",
    "iPhone11,6": "iPhone XS Max", "iPhone11,8": "iPhone XR",
    "iPhone12,1": "iPhone 11", "iPhone12,3": "iPhone 11 Pro", "iPhone12,5": "iPhone 11 Pro Max",
    "iPhone13,1": "iPhone 12 mini", "iPhone13,2": "iPhone 12",
    "iPhone13,3": "iPhone 12 Pro", "iPhone13,4": "iPhone 12 Pro Max",
    "iPhone14,2": "iPhone 13 Pro", "iPhone14,3": "iPhone 13 Pro Max",
    "iPhone14,4": "iPhone 13 mini", "iPhone14,5": "iPhone 13",
    "iPhone14,7": "iPhone 14", "iPhone14,8": "iPhone 14 Plus",
    "iPhone15,2": "iPhone 14 Pro", "iPhone15,3": "iPhone 14 Pro Max",
    "iPhone15,4": "iPhone 15", "iPhone15,5": "iPhone 15 Plus",
    "iPhone16,1": "iPhone 15 Pro", "iPhone16,2": "iPhone 15 Pro Max",
    "iPhone17,1": "iPhone 16 Pro", "iPhone17,2": "iPhone 16 Pro Max",
    "iPhone17,3": "iPhone 16", "iPhone17,4": "iPhone 16 Plus", "iPhone17,5": "iPhone 16e",
    "iPad1,1": "iPad", "iPad2,5": "iPad mini", "iPad2,7": "iPad mini",
    "iPad4,1": "iPad Air", "iPad4,4": "iPad mini 2", "iPad4,7": "iPad mini 3",
    "iPad5,1": "iPad mini 4", "iPad5,2": "iPad mini 4",
    "iPad5,3": "iPad Air 2", "iPad5,4": "iPad Air 2",
    "iPad6,7": "iPad Pro (12,9\")", "iPad6,8": "iPad Pro (12,9\")",
    "iPad6,11": "iPad (5e gen.)", "iPad6,12": "iPad (5e gen.)",
    "iPad7,1": "iPad Pro (12,9\")", "iPad7,2": "iPad Pro (12,9\")",
    "iPad7,5": "iPad (6e gen.)", "iPad7,6": "iPad (6e gen.)",
    "iPad11,1": "iPad mini (5e gen.)", "iPad11,2": "iPad mini (5e gen.)",
    "iPad11,6": "iPad (8e gen.)", "iPad11,7": "iPad (8e gen.)",
    "iPad13,1": "iPad Air (4e gen.)", "iPad13,2": "iPad Air (4e gen.)",
    "iPad13,16": "iPad Air (5e gen.)", "iPad13,17": "iPad Air (5e gen.)",
    "iPad14,1": "iPad mini (6e gen.)", "iPad14,2": "iPad mini (6e gen.)",
    "iPod5,1": "iPod touch (5e gen.)", "iPod7,1": "iPod touch (6e gen.)",
    "iPod9,1": "iPod touch (7e gen.)",
}
SAMSUNG_MODELS = {
    "SM-J710F": "Galaxy J7 (2016)", "SM-J710FN": "Galaxy J7 (2016)", "SM-J710MN": "Galaxy J7 (2016)",
    "SM-J730F": "Galaxy J7 (2017)", "SM-J530F": "Galaxy J5 (2017)", "SM-J600F": "Galaxy J6",
    "SM-A515F": "Galaxy A51", "SM-A525F": "Galaxy A52", "SM-A325F": "Galaxy A32",
    "SM-A217F": "Galaxy A21s", "SM-A217M": "Galaxy A21s",
    "SM-G950F": "Galaxy S8", "SM-G955F": "Galaxy S8+",
    "SM-G960F": "Galaxy S9", "SM-G965F": "Galaxy S9+",
    "SM-G970F": "Galaxy S10e", "SM-G973F": "Galaxy S10", "SM-G975F": "Galaxy S10+",
    "SM-G975U": "Galaxy S10+", "SM-G970U": "Galaxy S10e",
    "SM-G991B": "Galaxy S21", "SM-G996B": "Galaxy S21+", "SM-G998B": "Galaxy S21 Ultra",
    "SM-S901B": "Galaxy S22", "SM-S906B": "Galaxy S22+", "SM-S908B": "Galaxy S22 Ultra",
    "SM-S911B": "Galaxy S23", "SM-S916B": "Galaxy S23 Ultra",
    "SM-N975F": "Galaxy Note 10+", "SM-N970F": "Galaxy Note 10",
    "SM-T510": "Galaxy Tab A (10.1)", "SM-T515": "Galaxy Tab A (10.1)",
}


def fmt_storage(val):
    if val is None:
        return None
    try:
        n = int(str(val).split()[0])
        if n > 1_000_000_000_000:
            return f"{n / 1_000_000_000_000:.0f} To"
        if n > 1_000_000_000:
            return f"{n / 1_000_000_000:.0f} Go"
        if n > 1_000_000:
            return f"{n / 1_000_000:.0f} Mo"
        return str(n)
    except (ValueError, TypeError, IndexError):
        return str(val)[:40]


def b64name(v):
    try:
        s = base64.b64decode(v).decode("utf-8", "ignore")
        return s if s.isprintable() else None
    except Exception:
        return None


def model(code, brand):
    if not code:
        return None
    c = str(code).split("/")[0].strip()
    if c in APPLE_MODELS:
        return APPLE_MODELS[c]
    if c in SAMSUNG_MODELS:
        return SAMSUNG_MODELS[c]
    if c.upper().startswith("SM-"):
        return "Galaxy " + c[3:]
    return None


def main():
    root = sys.argv[1]
    overrides = {}
    for a in sys.argv[2:]:
        if "=" in a:
            k, v = a.split("=", 1)
            overrides[k] = v

    result = {k: (overrides.get(OVERRIDE.get(k, "")) or None) for k in ORDER}
    model_code = overrides.get("ModelCode") or None
    platform = overrides.get("Platform")

    # --- iOS : plists d'une backup iTunes (Info.plist / Manifest.plist) ---
    for name in ("Info.plist", "Manifest.plist"):
        pp = os.path.join(root, name)
        if not os.path.isfile(pp):
            continue
        try:
            with open(pp, "rb") as fh:
                d = plistlib.load(fh)
        except Exception:
            continue
        if name == "Info.plist":
            platform = platform or "iOS"
            model_code = model_code or d.get("Product Type") or d.get("ProductType") or d.get("Device Model")
            ver = d.get("Product Version") or d.get("ProductVersion") or d.get("iOS Version")
            build = d.get("Build Version") or d.get("BuildVersion")
            if ver:
                result["Systeme d exploitation"] = result["Systeme d exploitation"] or ("iOS " + str(ver))
            result["Build"] = result["Build"] or build
            result["Nom de l'appareil"] = result["Nom de l'appareil"] or \
                d.get("Device Name") or d.get("DeviceName")
            result["Numero de telephone"] = result["Numero de telephone"] or \
                d.get("Phone Number") or d.get("PhoneNumber")
            result["IMEI"] = result["IMEI"] or d.get("IMEI")
            result["Numero de serie"] = result["Numero de serie"] or \
                d.get("Serial Number") or d.get("SerialNumber")
            result["ICCID"] = result["ICCID"] or d.get("ICCID")
            result["MEID"] = result["MEID"] or d.get("MEID")
            result["Target identifier"] = result["Target identifier"] or \
                d.get("Unique Device ID") or d.get("UniqueDeviceID")
            result["Derniere sauvegarde"] = result["Derniere sauvegarde"] or \
                d.get("Last Backup Date") or d.get("LastBackupDate")
            result["Marque"] = result["Marque"] or "Apple"
        elif name == "Manifest.plist":
            result["Derniere sauvegarde"] = result["Derniere sauvegarde"] or \
                d.get("Date") or d.get("LastBackupDate")

    # --- iOS : backup_info.json / sysdiagnose_info.json ---
    for name in ("backup_info.json", "sysdiagnose_info.json"):
        p = os.path.join(root, name)
        if not os.path.isfile(p):
            continue
        try:
            d = json.load(open(p, encoding="utf-8"))
        except Exception:
            continue
        platform = "iOS"
        model_code = model_code or search(d, ("Product Type", "product_type", "ProductType", "model"))
        ver = search(d, ("Product Version", "product_version", "ProductVersion", "ios_version"))
        build = search(d, ("Build Version", "build_version", "BuildVersion"))
        if ver:
            result["Systeme d exploitation"] = result["Systeme d exploitation"] or ("iOS " + str(ver))
        result["Build"] = result["Build"] or build
        result["Nom de l'appareil"] = result["Nom de l'appareil"] or \
            b64name(search(d, ("Display Name",)) or "") or search(d, ("Device Name", "device_name", "name", "Devicename"))
        result["Numero de telephone"] = result["Numero de telephone"] or \
            search(d, ("Phone Number", "phone_number", "PhoneNumber"))
        result["IMEI"] = result["IMEI"] or search(d, ("IMEI", "imei"))
        result["Numero de serie"] = result["Numero de serie"] or \
            search(d, ("Serial Number", "serial_number", "SerialNumber", "Serial"))
        result["ICCID"] = result["ICCID"] or search(d, ("ICCID", "iccid"))
        result["MEID"] = result["MEID"] or search(d, ("MEID", "meid"))
        result["Target identifier"] = result["Target identifier"] or \
            search(d, ("Target Identifier", "target_identifier", "Unique Identifier", "unique_identifier"))
        result["Derniere sauvegarde"] = result["Derniere sauvegarde"] or \
            search(d, ("Last Backup Date", "last_backup_date", "LastBackupDate"))
        apps = search(d, ("Installed Applications", "installed_applications"))
        if isinstance(apps, list) and apps:
            result["Applications installees"] = result["Applications installees"] or f"{len(apps)} application(s)"
        result["Marque"] = result["Marque"] or "Apple"
        break

    # --- Android : acquisition.json ---
    if platform != "iOS":
        p = os.path.join(root, "acquisition.json")
        if os.path.isfile(p):
            try:
                d = json.load(open(p, encoding="utf-8"))
            except Exception:
                d = {}
            platform = "Android"
            model_code = model_code or search(d, ("product_model", "model", "device_model"))
            ver = search(d, ("device_version", "android_version", "version", "os_version"))
            if ver:
                result["Systeme d exploitation"] = result["Systeme d exploitation"] or ("Android " + str(ver))
            result["Marque"] = result["Marque"] or \
                search(d, ("product_manufacturer", "manufacturer", "brand"))
            result["IMEI"] = result["IMEI"] or search(d, ("imei", "imei1", "Imei"))
            serial = result["Numero de serie"] or search(d, ("serial_number", "serial", "Serial"))
            if not serial:
                adb = search(d, ("collector", "Adb"))
                if isinstance(adb, dict):
                    serial = adb.get("Serial")
            result["Numero de serie"] = result["Numero de serie"] or serial

    # --- Android : getprop.txt ---
    p = os.path.join(root, "getprop.txt")
    if os.path.isfile(p):
        try:
            txt = open(p, encoding="utf-8", errors="ignore").read()
            gmap = {
                "ro.product.model": "Modele",
                "ro.product.manufacturer": "Marque",
                "ro.build.version.short": "Build",
                "ro.build.version.incremental": "Build",
                "ro.build.display.id": "Build",
                "ro.build.version.security_patch": "Dernier patch de securite",
                "ro.ril.oem.imei": "IMEI",
                "ro.serialno": "Numero de serie",
            }
            mrel = re.search(r'\[ro\.build\.version\.release\]:\s*\[([^\]]*)\]', txt)
            if mrel and mrel.group(1):
                result["Systeme d exploitation"] = result["Systeme d exploitation"] or ("Android " + mrel.group(1))
            for key, field in gmap.items():
                if result[field]:
                    continue
                m = re.search(r'\[' + re.escape(key) + r'\]:\s*\[([^\]]*)\]', txt)
                if m and m.group(1):
                    result[field] = m.group(1)
            if not result["Capacite stockage"]:
                for key in ("ro.product.disk.size", "ro.emmc.size"):
                    m = re.search(r'\[' + re.escape(key) + r'\]:\s*\[([^\]]*)\]', txt)
                    if m and m.group(1):
                        result["Capacite stockage"] = fmt_storage(m.group(1))
                        break
        except Exception:
            pass

    # --- Compteur d'applications Android ---
    if not result["Applications installees"]:
        for name in ("aqf_packages.json", "dumpsys_packages.json"):
            ap = os.path.join(root, name)
            if os.path.isfile(ap):
                try:
                    alist = json.load(open(ap, encoding="utf-8"))
                    if isinstance(alist, list):
                        n = len([x for x in alist if isinstance(x, dict) and x.get("name")])
                        if n:
                            result["Applications installees"] = f"{n} application(s)"
                            break
                except Exception:
                    pass

    # --- Modèle + code ---
    if not result["Modele"] and model_code:
        model = model(model_code, result["Marque"])
        result["Modele"] = f"{model} ({model_code})" if model else str(model_code)
    elif result["Modele"]:
        model = model(result["Modele"], result["Marque"])
        if model and model != str(result["Modele"]):
            result["Modele"] = f"{model} ({result['Modele']})"

    for field in ORDER:
        val = result[field]
        if val not in (None, "", "non disponible"):
            print(f"{field}\t{str(val)[:170]}")


if __name__ == "__main__":
    main()
