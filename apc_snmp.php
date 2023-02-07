<?php
//version 2.0 dated 2/9/2022
//by Brian Wallace

///////////////////////////////////////////////////
//User Defined Variables
///////////////////////////////////////////////////
$config_file="/volume1/web/config/config_files/config_files_local/FB_APC_config.txt";
$use_login_sessions=true; //set to false if not using user login sessions
$form_submittal_destination="index.php?page=6&config_page=bedroom_apc"; //set to the destination the HTML form submit should be directed 
$page_title="First Floor Bedroom APC UPS Logging Configuration Settings";

///////////////////////////////////////////////////
//Beginning of configuration page
///////////////////////////////////////////////////
if($use_login_sessions){
	if($_SERVER['HTTPS']!="on") {

	$redirect= "https://".$_SERVER['HTTP_HOST'].$_SERVER['REQUEST_URI'];

	header("Location:$redirect"); } 

	// Initialize the session
	if(session_status() !== PHP_SESSION_ACTIVE) session_start();
	 
	// Check if the user is logged in, if not then redirect him to login page
	if(!isset($_SESSION["loggedin"]) || $_SESSION["loggedin"] !== true){
		header("location: login.php");
		exit;
	}
}
error_reporting(E_NOTICE);
include $_SERVER['DOCUMENT_ROOT']."/functions.php";

$email_error=0;
$email_interval_error=0;
$url_error="";
$name_error="";
$ups_group_error="";
$influxdb_host_error="";
$influxdb_port_error="";
$influxdb_name_error="";
$influxdb_user_error="";
$influxdb_pass_error="";
$generic_error="";
$AuthPass1_error="";
$PrivPass2_error="";
$snmp_user_error="";
		
		
if (file_exists("$config_file")) {
	$data = file_get_contents("$config_file");
	$pieces = explode(",", $data);
	$capture_interval=$pieces[0];
	$url=$pieces[1];
	$name=$pieces[2];
	$ups_group=$pieces[3];
	$influxdb_host=$pieces[4];
	$influxdb_port=$pieces[5];
	$influxdb_name=$pieces[6];
	$influxdb_user=$pieces[7];
	$influxdb_pass=$pieces[8];
	$script_enable=$pieces[9];
	$AuthPass1=$pieces[10];
	$PrivPass2=$pieces[11];
	$snmp_user=$pieces[12];
	$snmp_privacy_protocol=$pieces[13];
	$snmp_auth_protocol=$pieces[14];
}else{
	$capture_interval=60;
	$url="localhost";
	$name="";
	$ups_group="NAS";
	$influxdb_host=0;
	$influxdb_port=8086;
	$influxdb_name="db";
	$influxdb_user="admin";
	$influxdb_pass="password";
	$script_enable=0;
	$AuthPass1="password1";
	$PrivPass2="password2";
	$snmp_user="user";
	$snmp_privacy_protocol="AES";
	$snmp_auth_protocol="MD5";
	
	$put_contents_string="".$capture_interval.",".$url.",".$name.",".$ups_group.",".$influxdb_host.",".$influxdb_port.",".$influxdb_name.",".$influxdb_user.",".$influxdb_pass.",".$script_enable.",".$AuthPass1.",".$PrivPass2.",".$snmp_user.",".$snmp_privacy_protocol.",".$snmp_auth_protocol."";
  
	if (file_put_contents("$config_file",$put_contents_string )==FALSE){
		print "<font color=\"red\">Error -- could not save new configuration values</font>";
	}
}

if(isset($_POST['submit_APC'])){
		   
	//perform data verification of submitted values
	[$script_enable, $generic_error] = test_input_processing($_POST['script_enable'], 0, "checkbox", 0, 0);
		  
	if ($_POST['capture_interval']==10 || $_POST['capture_interval']==15 || $_POST['capture_interval']==30 || $_POST['capture_interval']==60){
		$capture_interval=htmlspecialchars($_POST['capture_interval']);
	}
	
	
	if ($_POST['snmp_privacy_protocol']=="AES" || $_POST['snmp_privacy_protocol']=="DES"){
		[$snmp_privacy_protocol, $generic_error] = test_input_processing($_POST['snmp_privacy_protocol'], $pieces[13], "name", 0, 0);
	}else{
		$snmp_privacy_protocol=$pieces[13];
	}
		   
		   //perform data verification of submitted values
	if ($_POST['snmp_auth_protocol']=="MD5" || $_POST['snmp_auth_protocol']=="SHA"){
		[$snmp_auth_protocol, $generic_error] = test_input_processing($_POST['snmp_auth_protocol'], $pieces[14], "name", 0, 0);
	}else{
		$snmp_auth_protocol=$pieces[14];
	}
	[$snmp_user, $snmp_user_error] = test_input_processing($_POST['snmp_user'], $pieces[12], "name", 0, 0);
		
	[$PrivPass2, $PrivPass2_error] = test_input_processing($_POST['PrivPass2'], $pieces[11], "password", 0, 0);
		  
	[$AuthPass1, $AuthPass1_error] = test_input_processing($_POST['AuthPass1'], $pieces[10], "password", 0, 0);   
			  
	[$url, $url_error] = test_input_processing($_POST['url'], $url, "ip", 0, 0);

	[$name, $name_error] = test_input_processing($_POST['name'], $name, "name", 0, 0);
		
	[$ups_group, $ups_group_error] = test_input_processing($_POST['ups_group'], $ups_group, "name", 0, 0);
		
	[$influxdb_host, $influxdb_host_error] = test_input_processing($_POST['influxdb_host'], $influxdb_host, "ip", 0, 0);
		
	[$influxdb_port, $influxdb_port_error] = test_input_processing($_POST['influxdb_port'], $influxdb_port, "numeric", 1, 65000);
		
	[$influxdb_name, $influxdb_name_error] = test_input_processing($_POST['influxdb_name'], $influxdb_name, "name", 0, 0);
		
	[$influxdb_user, $influxdb_user_error] = test_input_processing($_POST['influxdb_user'], $influxdb_user, "name", 0, 0);
		  
	[$influxdb_pass, $influxdb_pass_error] = test_input_processing($_POST['influxdb_pass'], $influxdb_pass, "password", 0, 0); 
		  
	$put_contents_string="".$capture_interval.",".$url.",".$name.",".$ups_group.",".$influxdb_host.",".$influxdb_port.",".$influxdb_name.",".$influxdb_user.",".$influxdb_pass.",".$script_enable.",".$AuthPass1.",".$PrivPass2.",".$snmp_user.",".$snmp_privacy_protocol.",".$snmp_auth_protocol."";
		  
	if (file_put_contents("$config_file",$put_contents_string )==FALSE){
		print "<font color=\"red\">APC Communications Error --> Check network connections and verify operation of APC</font>";
	}
		  
}
	   
print "<br><fieldset><legend><h3>".$page_title."</h3></legend>	
<table border=\"0\">
	<tr>
		<td>";
			if ($script_enable==1){
				print "<font color=\"green\"><h3>Script Status: Active</h3></font>";
			}else{
				print "<font color=\"red\"><h3>Script Status: Inactive</h3></font>";
			}
print "
		</td>
	</tr>
	<tr>
		<td align=\"left\">
			<form action=\"".$form_submittal_destination."\" method=\"post\">
				<p><input type=\"checkbox\" name=\"script_enable\" value=\"1\" ";
				   if ($script_enable==1){
						print "checked";
				   }
print "
					>Enable Entire Script?
				</p>
				<br>
				<b>SNMP SETTINGS</b>
				<p>->IP of UPS to gather SNMP Information from: <input type=\"text\" name=\"url\" value=".$url."> ".$url_error."</p>
				<p>->Name of UPS: <input type=\"text\" name=\"name\" value=".$name."> ".$name_error."</p>
				<p>->SNMP Username: <input type=\"text\" name=\"snmp_user\" value=".$snmp_user."> ".$snmp_user_error."</p>
				<p>->Authorization Protocol: <select name=\"snmp_auth_protocol\">";
					if ($snmp_auth_protocol=="MD5"){
						print "<option value=\"MD5\" selected>MD5</option>
						<option value=\"SHA\">SHA</option>";
					}else if ($snmp_auth_protocol=="SHA"){
						print "<option value=\"MD5\">MD5</option>
						<option value=\"SHA\" selected>SHA</option>";
					}
print "				</select></p>
					<p>->Privacy Protocol: <select name=\"snmp_privacy_protocol\">";
					if ($snmp_privacy_protocol=="AES"){
						print "<option value=\"AES\" selected>AES</option>
						<option value=\"DES\">DES</option>";
					}else if ($snmp_privacy_protocol=="DES"){
						print "<option value=\"AES\">AES</option>
						<option value=\"DES\" selected>DES</option>";
					}
print "				</select></p>
				<br>
				<b>INFLUXDB SETTINGS</b>
				<p>->IP of Influx DB: <input type=\"text\" name=\"influxdb_host\" value=".$influxdb_host."> ".$influxdb_host_error."</p>
				<p>->PORT of Influx DB: <input type=\"text\" name=\"influxdb_port\" value=".$influxdb_port."> ".$influxdb_port_error."</p>
				<p>->Database to use within Influx DB: <input type=\"text\" name=\"influxdb_name\" value=".$influxdb_name."> ".$influxdb_name_error."</p>
				<p>->User Name of Influx DB: <input type=\"text\" name=\"influxdb_user\" value=".$influxdb_user."> ".$influxdb_user_error."</p>
				<p>->Password of Influx DB: <input type=\"text\" name=\"influxdb_pass\" value=".$influxdb_pass."> ".$influxdb_pass_error."</p>
				<center><input type=\"submit\" name=\"submit_APC\" value=\"Submit\" /></center>
			</form>
		</td>
	</tr>
</table>
</fieldset>";
?>
