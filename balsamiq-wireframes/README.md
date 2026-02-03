# Balsamiq Wireframes - Export Instructions

## Files Included

| File | Description |
|------|-------------|
| `01-api-gateway-architecture.bmml` | API Gateway + VPC Link architecture |
| `02-spring-cloud-gateway-architecture.bmml` | ALB + Spring Cloud Gateway architecture |
| `03-api-gateway-failover.bmml` | API Gateway multi-region failover |
| `04-spring-gateway-failover.bmml` | Spring Gateway multi-region failover |
| `05-global-accelerator.bmml` | Global Accelerator fastest failover |
| `06-full-production-architecture.bmml` | Complete multi-region production architecture |

---

## How to Export PNG Images

### Option 1: Balsamiq Mockups Desktop

1. Open Balsamiq Mockups
2. **File → Import → BMML**
3. Select the `.bmml` file
4. **File → Export → Current Mockup to PNG**
5. Save as:
   - `01-api-gateway-architecture.png`
   - `02-spring-cloud-gateway-architecture.png`
   - `03-api-gateway-failover.png`
   - `04-spring-gateway-failover.png`
   - `05-global-accelerator.png`
   - `06-full-production-architecture.png`

### Option 2: Balsamiq Cloud

1. Go to [balsamiq.cloud](https://balsamiq.cloud)
2. Create a new project
3. **Project → Import → BMML**
4. Export each mockup as PNG

### Option 3: Batch Export (Balsamiq Desktop)

```bash
# If you have all BMML files in a project
# File → Export → All Mockups to PNG
```

---

## Upload to Confluence

After exporting PNG files:

1. Go to your Confluence page
2. Click **Edit**
3. Click **Insert → Files and Images**
4. Upload all 6 PNG files
5. They will automatically be linked in the Confluence XML

---

## Expected PNG Filenames

The Confluence XML references these exact filenames:

```
01-api-gateway-architecture.png
02-spring-cloud-gateway-architecture.png
03-api-gateway-failover.png
04-spring-gateway-failover.png
05-global-accelerator.png
06-full-production-architecture.png
```

Make sure to use these exact names when exporting.

---

## Alternative: Use Online BMML Viewer

If you don't have Balsamiq:

1. Use [MockFlow](https://mockflow.com) - Import BMML
2. Use [Figma](https://figma.com) with Balsamiq plugin
3. Convert manually using online XML viewers
