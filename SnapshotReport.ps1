#Open vCenter1 Connection // Create authentication config.xml:
function connect {
	if (-not (Test-Path "$PSScriptRoot\config.xml")) {
		Write-Host ""
		$hostname = Read-Host "Input Hostname" 
		$user = Read-Host "Input Domain\User"
		$password = Read-Host "Input Password" 
		New-VICredentialStoreItem -Host $hostname -User $user -Password $password -File "$PSScriptRoot\config.xml"
	}

	$config = Get-VICredentialStoreItem -File "$PSScriptRoot\config.xml"
	$connected = Connect-VIServer -Server $config.Host -User $config.User -Password $config.Password -Force
	return $connected
}
#Global Variables:
$germanCulture = [System.Globalization.CultureInfo]::GetCultureInfo("de-DE")

#Functions:
function sendEmail {

	$MailParam = @{
		To         = "$address"
		From       = "Snapshot Management <no-reply@myCompany.com>"
		SmtpServer = "smtp.myCompany.com"
		Subject    = "VMware Snapshot Alert for $($vm.Name) - " + (Get-Date -Format M/d/yyyy)
		body       = $mailMap.$mailType
	}
	Send-MailMessage @MailParam -BodyAsHtml
}
function notifyContacts {
	$contact = (Get-TagAssignment -Entity $vm -Category Contact | Select-Object -ExpandProperty Tag).Description

	foreach ($address in $Contact) {
		#If no contact, vmware admins until contact is updated.
		if ($address -notlike "*@myCompany.com") {
			$contact = "vmware.admins@myCompany.com"
		}
		$mailMap = @{
			"warn"   = ([string]"The protected snapshot $($snap.Name), found on $($vm.Name) is $snapAge days old and will be deleted tomorrow.<br><br>If you have a <b><i>business need</i></b> to extend the snapshot retention, please open a work order ASAP and assign it to Infrastructure Converged.<br>Do not reply to this email.<br><br><br><i>NOTE:</i> Protected snapshot retention requires management approval.")
			"delete" = ([string]"This is a courtesy reminder.<br><br>Snapshot $($snap.Name), found on $($vm.Name) will be deleted tomorrow.")
		}
		#sendEmail
	}
}
function getSnapshots() {
	$clusterName = (Get-Cluster).Name
	$vmSnapshotsList = Get-VM | Get-Snapshot
	$snapshotCount = ($vmSnapshotsList | Measure-Object).Count
	$snapshotSizeMax = [Math]::Round(($vmSnapshotsList | Measure-Object -Property SizeMB -Sum).Sum, 2)
	$oldestSnapshot = (($vmSnapshotsList | Sort-Object -Property Created | Select-Object -First 1).Created).ToString("d", $germanCulture)
	$vmSnapshots = @{}
	foreach ($snap in $vmSnapshotsList) {
		if (-not $vmSnapshots.ContainsKey($snap.VM.Name)) {
			$vmSnapshots[$snap.VM.Name] = @()
			$vmSnapshots[$snap.VM.Name] += ($snap)
		}
		else {
			$vmSnapshots[$snap.VM.Name] += ($snap)
		}
	}

	
	# Start HTML content
	$html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Snapshots</title>
    <style>
				body {
						font-family:"Tahoma"
				}
        table {
            width: 90%;
            border-collapse: collapse;
        }
        table, th, td {
            border: 1px solid black;
        }
        th, td {
            padding: 10px;
            text-align: left;
        }
        th {
            background-color: #f2f2f2;
        }
        .collapsible {
            cursor: pointer;
						background-color: #BBE9FF
        }
        .collapsible-content {
            display: none;
						background-color: #FFE9D0
        }
				td:first-child  {
 						font-size: larger;
						width: 300px;
				}
				.container {
            display: flex;
            justify-content: space-around;
            align-items: center;
            width: 100%;
            height: 20vh;
        }
        .box {
            width: 30%;
            padding: 20px;
            border: 1px solid #000;
            box-shadow: 0 0 10px rgba(0, 0, 0, 0.1);
            text-align: center;
				}
    </style>
</head>
<body>
    <h2>Snapshot Report of $($clusterName)</h2>
		<div class="container">
    <div class="box">
        <h3>Snapshots</h3>
        <h2>$($snapshotCount)</h2>
    </div>
    <div class="box">
        <h3>Space</h3>
				<h2>$($snapshotSizeMax) mb</h2>
    </div>
    <div class="box">
        <h3>Oldest</h3>
				<h2>$($oldestSnapshot)<h2>
    </div>
</div>
		<button id="toggleButton" onclick="toggleCollapse()">Expand All</button>
    <table>
        <tr>
            <th>Virtual Machine</th>
            <th>Snapshot Name</th>
            <th>Size in MB</th>
            <th>Created</th>
            <th>Parent</th>
        </tr>
"@

	# Add rows to the table
	foreach ($vm in $vmSnapshots.GetEnumerator()) {
		$html += "<tr class='collapsible'>"
		$html += "<td colspan='5'>$($vm.Key)</td>"
		$html += "</tr>"
		foreach ($snap in $vm.Value ) {
			$html += "<tr class='collapsible-content'>"
			$html += "<td></td>"
			$html += "<td>$($snap.Name)</td>"
			$html += "<td>$([Math]::Round($snap.SizeMB,2))</td>"
			$html += "<td>$(($snap.Created).ToString("d", $germanCulture))</td>"
			$html += "<td>$($snap.ParentSnapshot)"
			$html += "</tr>"
		}
	}

	# End HTML content
	$html += @"
    </table>
		<script>
    document.querySelectorAll('.collapsible').forEach(function(row) {
        row.addEventListener('click', function() {
            this.classList.toggle('active');
            var contentRows = this.nextElementSibling;
            while (contentRows && contentRows.classList.contains('collapsible-content')) {
                contentRows.style.display = contentRows.style.display === 'table-row' ? 'none' : 'table-row';
                contentRows = contentRows.nextElementSibling;
            }
        });
    });
    function toggleCollapse() {
        const button = document.getElementById('toggleButton');
        const rows = document.querySelectorAll('.collapsible-content');
        const isCollapsed = Array.from(rows).every(row => row.style.display === 'none');

        if (isCollapsed) {
            rows.forEach(row => row.style.display = 'table-row');
            button.innerText = 'Collapse All';
        } else {
            rows.forEach(row => row.style.display = 'none');
            button.innerText = 'Expand All';
        }
    }
    // Ensure all are collapsed by default
		toggleCollapse()
</script>
</body>
</html>
"@

	# Output HTML to a file
	$html | Out-File -FilePath "$PSScriptRoot\results.html" -Encoding utf8
}

#Main:
if (connect) {
	getSnapshots
	Disconnect-VIServer -Server * -Confirm:$false -Force -ErrorAction SilentlyContinue
}