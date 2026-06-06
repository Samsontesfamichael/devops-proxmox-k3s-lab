#!/bin/bash
# 1. Create the new user on the PVE realm
pveum user add terraform1@pve --comment "Terraform Automation"

# 2. Create a dedicated API token for this user (disable privilege separation)
pveum user token add terraform1@pve terraform-token --privsep 0

# 3. Define a custom role with required automation permissions
pveum role add TerraformRole -privs "VM.Allocate VM.Clone VM.Config.CDROM VM.Config.CPU VM.Config.Disk VM.Config.HWType VM.Config.Memory VM.Config.Network VM.Config.Options VM.Monitor VM.PowerMgmt Datastore.AllocateSpace Datastore.Audit SDN.Use"

# 4. Assign the role to your API token at the root path
pveum acl modify / --token "terraform1@pve!terraform-token" --role TerraformRole
