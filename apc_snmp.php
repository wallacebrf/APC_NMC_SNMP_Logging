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
error_reporting(E_ALL ^ E_NOTICE);
include $_SERVER['DOCUMENT_ROOT']."/functions.php";

$APC_email_error=0;
$APC_email_interval_error=0;
$APC_APC_url_error="";
$APC_APC_name_error="";
$APC_ups_group_error="";
$APC_influxdb_host_error="";
$APC_influxdb_port_error="";
$APC_influxdb_name_error="";
$APC_influxdb_user_error="";
$APC_influxdb_pass_error="";
$generic_error="";
		
		
if (file_exists("$config_file")) {
	$data = file_get_contents("$config_file");
	$pieces = explode(",", $data);
	$APC_capture_interval=$pieces[0];
	$APC_APC_url=$pieces[1];
	$APC_APC_name=$pieces[2];
	$APC_ups_group=$pieces[3];
	$APC_influxdb_host=$pieces[4];
	$APC_influxdb_port=$pieces[5];
	$APC_influxdb_name=$pieces[6];
	$APC_influxdb_user=$pieces[7];
	$APC_influxdb_pass=$pieces[8];
	$APC_script_enable=$pieces[9];
}else{
	$APC_capture_interval=60;
	$APC_APC_url="localhost";
	$APC_APC_name="";
	$APC_ups_group="NAS";
	$APC_influxdb_host=0;
	$APC_influxdb_port=8086;
	$APC_influxdb_name="db";
	$APC_influxdb_user="admin";
	$APC_influxdb_pass="password";
	$APC_script_enable=0;
	$put_contents_string="".$APC_capture_interval.",".$APC_APC_url.",".$APC_APC_name.",".$APC_ups_group.",".$APC_influxdb_host.",".$APC_influxdb_port.",".$APC_influxdb_name.",".$APC_influxdb_user.",".$APC_influxdb_pass.",".$APC_script_enable."";
  
	if (file_put_contents("$config_file",$put_contents_string )==FALSE){
		print "<font color=\"red\">Error -- could not save new configuration values</font>";
	}
}

if(isset($_POST['submit_APC'])){
		   
	//perform data verification of submitted values
	[$APC_script_enable, $generic_error] = test_input_processing($_POST['APC_script_enable'], 0, "checkbox", 0, 0);
		  

	if ($_POST['APC_capture_interval']==10 || $_POST['APC_capture_interval']==15 || $_POST['APC_capture_interval']==30 || $_POST['APC_capture_interval']==60){
		$APC_capture_interval=htmlspecialchars($_POST['APC_capture_interval']);
	}
		  
	[$APC_APC_url, $APC_APC_url_error] = test_input_processing($_POST['APC_APC_url'], $APC_APC_url, "ip", 0, 0);

	[$APC_APC_name, $APC_APC_name_error] = test_input_processing($_POST['APC_APC_name'], $APC_APC_name, "name", 0, 0);
		
	[$APC_ups_group, $APC_ups_group_error] = test_input_processing($_POST['APC_ups_group'], $APC_ups_group, "name", 0, 0);
		
	[$APC_influxdb_host, $APC_influxdb_host_error] = test_input_processing($_POST['APC_influxdb_host'], $APC_influxdb_host, "ip", 0, 0);
		
	[$APC_influxdb_port, $APC_influxdb_port_error] = test_input_processing($_POST['APC_influxdb_port'], $APC_influxdb_port, "numeric", 1, 65000);
		
	[$APC_influxdb_name, $APC_influxdb_name_error] = test_input_processing($_POST['APC_influxdb_name'], $APC_influxdb_name, "name", 0, 0);
		
	[$APC_influxdb_user, $APC_influxdb_user_error] = test_input_processing($_POST['APC_influxdb_user'], $APC_influxdb_user, "name", 0, 0);
		  
	[$APC_influxdb_pass, $APC_influxdb_pass_error] = test_input_processing($_POST['APC_influxdb_pass'], $APC_influxdb_pass, "password", 0, 0); 
		  
	$put_contents_string="".$APC_capture_interval.",".$APC_APC_url.",".$APC_APC_name.",".$APC_ups_group.",".$APC_influxdb_host.",".$APC_influxdb_port.",".$APC_influxdb_name.",".$APC_influxdb_user.",".$APC_influxdb_pass.",".$APC_script_enable."";
		  
	if (file_put_contents("$config_file",$put_contents_string )==FALSE){
		print "<font color=\"red\">APC Communications Error --> Check network connections and verify operation of APC</font>";
	}
		  
}
	   
print "<br><fieldset><legend><h3>".$page_title."</h3></legend>	
<table border=\"0\">
	<tr>
		<td>";
			if ($APC_script_enable==1){
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
				<p><input type=\"checkbox\" name=\"APC_script_enable\" value=\"1\" ";
				   if ($APC_script_enable==1){
						print "checked";
				   }
print "
					>Enable Entire Script?
				</p>
				<p>IP of UPS to gather SNMP Information from: <input type=\"text\" name=\"APC_APC_url\" value=".$APC_APC_url."> ".$APC_APC_url_error."</p>
				<p>Name of UPS: <input type=\"text\" name=\"APC_APC_name\" value=".$APC_APC_name."> ".$APC_APC_name_error."</p>
				<p>IP of Influx DB: <input type=\"text\" name=\"APC_influxdb_host\" value=".$APC_influxdb_host."> ".$APC_influxdb_host_error."</p>
				<p>PORT of Influx DB: <input type=\"text\" name=\"APC_influxdb_port\" value=".$APC_influxdb_port."> ".$APC_influxdb_port_error."</p>
				<p>Database to use within Influx DB: <input type=\"text\" name=\"APC_influxdb_name\" value=".$APC_influxdb_name."> ".$APC_influxdb_name_error."</p>
				<p>User Name of Influx DB: <input type=\"text\" name=\"APC_influxdb_user\" value=".$APC_influxdb_user."> ".$APC_influxdb_user_error."</p>
				<p>Password of Influx DB: <input type=\"text\" name=\"APC_influxdb_pass\" value=".$APC_influxdb_pass."> ".$APC_influxdb_pass_error."</p>
				<center><input type=\"submit\" name=\"submit_APC\" value=\"Submit\" /></center>
			</form>
		</td>
	</tr>
</table>
</fieldset>";
?>
