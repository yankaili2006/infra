job "sandbox-test" {
  datacenters = ["dc1"]
  type = "service"

  group "sandbox" {
    count = 1

    task "create-vm" {
      driver = "raw_exec"

      config {
        command = "/mnt/sdb/pcloud/infra/packages/orchestrator/bin/orchestrator"
        args = [
          "create-vm",
          "--templateID", "base-template-000-0000-0000-000000000001",
          "--teamID", "cfee9a8f-dbbc-4970-9180-d0de5a28148f",
        ]
      }

      resources {
        cpu    = 500
        memory = 256
      }
    }
  }
}
