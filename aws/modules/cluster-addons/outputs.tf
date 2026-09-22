# No outputs, on purpose. These add-ons are consumed by the cluster itself and
# by scripts (kots-install.sh asserts the load balancer controller is healthy
# via kubectl), never by other Terraform — an output here would invent a
# contract nothing holds.
