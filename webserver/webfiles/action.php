<?php
$servername = "db.cyber23.test";
$fullname = "wwwclient23";
$password = rtrim(file_get_contents("/run/secrets/db_password"));
$dbname = "csvs23db";

// Create connection
$conn = new mysqli($servername, $fullname, $password, $dbname);

// Check connection
if ($conn->connect_error) {
    die("Connection failed: " . $conn->connect_error);
}



print_r($_POST);
$fullnamedata = $_POST['fullname'];
$suggestiondata = $_POST['suggestion'];

$stmt = $conn->prepare("INSERT INTO suggestion (fullname, suggestion) VALUES (?, ?)");
// Check for the SQL injection 
$stmt->bind_param("ss", $fullnamedata, $suggestiondata);

$stmt->execute();
$stmt->close();
$conn->close();

header( 'Location: /index.php' ) ;

?>
