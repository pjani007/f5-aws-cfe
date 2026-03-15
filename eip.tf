resource "aws_eip" "mgmt_eip" { 
    count             = 2 
    domain            = "vpc" 
    # Attach directly to the management ENIs defined in eni.tf 
    network_interface = aws_network_interface.mgmt[count.index].id 
    
    tags = { 
        Name = "bigip-${count.index + 1}-mgmt-eip" 
    } 
}