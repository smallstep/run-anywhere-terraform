#----------------------------------------------------------------------------------
# 
# Variables to create basic rules that should be available in all Security Groups
# 
#----------------------------------------------------------------------------------

variable "public_facing" {
  default     = false
  description = "Sets a public facing resource in the rule set."
}

variable "security_group_id" {
  description = "Security group to which we are attaching the base rules."
}