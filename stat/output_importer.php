<?php
mysql_connect('localhost','root','root');
mysql_select_db('prezi');
$a = fopen('output.log','r');
$linecount = 0;

$handle = fopen('output.log', "r");
echo 'Initializing...'."\n";
while(!feof($handle)){
  $line = fgets($handle);
  $linecount++;
}
fclose($handle);
echo "Input file has $linecount lines.\n";
$percentage = 0;
$line = 0;
//2013-03-01 16:11:04 url 19 8 5

while ($b = fgets($a)) {
	$items = explode(' ',$b);
	$day = explode('-',$items[0]);
	$time = explode(':',$items[1]);
	
	//echo 'INSERT INTO output(d,h,m,s,queue,_max,_free,_min) VALUES('.$day[2].','.$time[0].','.$time[1].','.$time[2].',"'.$items[2].'",'.$items[3].','.$items[4].','.$items[5].');';
	mysql_query('INSERT INTO output(d,h,m,s,queue,_max,_free,_min) VALUES('.$day[2].','.$time[0].','.$time[1].','.$time[2].',"'.$items[2].'",'.$items[3].','.$items[4].','.$items[5].');');
	$line++;
	if ($line % 1000 == 0) {
		echo $line."/"."$linecount line (".($line/$linecount*100)."%) done. \n";
	}
	
}


?>