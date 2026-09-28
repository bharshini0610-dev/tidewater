"""Capture real UI screenshots of Prometheus, Alertmanager and Grafana for the evidence.

Usage: screenshots.py <label> <outdir>   (expects port-forwards on 9090, 9093, 3000)
"""

import base64
import os
import subprocess
import sys
import time

from playwright.sync_api import sync_playwright

label, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)


def pf(ns, svc, ports):
    subprocess.Popen(["kubectl", "-n", ns, "port-forward", f"svc/{svc}", ports],
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


pf("monitoring", "kps-kube-prometheus-stack-alertmanager", "9093:9093")
pf("monitoring", "kps-grafana", "3000:80")
time.sleep(4)
pw_b64 = subprocess.run(
    ["kubectl", "-n", "monitoring", "get", "secret", "kps-grafana", "-o", "jsonpath={.data.admin-password}"],
    capture_output=True, text=True, check=True).stdout
grafana_pw = base64.b64decode(pw_b64).decode()

with sync_playwright() as p:
    b = p.chromium.launch()
    page = b.new_page(viewport={"width": 1600, "height": 1000})
    page.goto("http://localhost:9090/alerts?search=Settle", wait_until="networkidle")
    time.sleep(2)
    for sel in ["text=SettleApiErrorBudgetBurn", "text=firing"]:
        try:
            page.locator(sel).first.click(timeout=2000)
        except Exception:  # noqa: BLE001 - UI differs across versions; screenshot anyway
            pass
    time.sleep(1)
    page.screenshot(path=f"{out}/{label}-prometheus-alerts.png", full_page=True)
    page.goto("http://localhost:9093/#/alerts", wait_until="networkidle")
    time.sleep(3)
    page.screenshot(path=f"{out}/{label}-alertmanager.png", full_page=True)
    ctx = b.new_context(viewport={"width": 1700, "height": 1250},
                        http_credentials={"username": "admin", "password": grafana_pw})
    g = ctx.new_page()
    g.goto("http://localhost:3000/d/settle-overview/settle?orgId=1&from=now-20m&to=now&kiosk",
           wait_until="networkidle")
    time.sleep(8)
    g.screenshot(path=f"{out}/{label}-grafana.png", full_page=True)
    b.close()
print("screenshots written to", out)
