job "sandbox-test-batch" {
  datacenters = ["dc1"]
  type = "batch"

  group "sandbox" {
    count = 1

    task "create-vm" {
      driver = "raw_exec"

      config {
        command = "sudo"
        args = [
          "/mnt/sdb/pcloud/infra/packages/orchestrator/bin/orchestrator",
          "create-sandbox",
          "--templateID", "base-template-000-0000-0000-000000000001",
          "--teamID", "cfee9a8f-dbbc-4970-9180-d0de5a28148f",
        ]
      }

      resources {
        cpu    = 250
        memory = 128
      }
    }
  }
}
