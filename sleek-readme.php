<?php
$path = $argv[1] ?? null;

if ($path) {
	$output = "";

	foreach (glob($path) as $file) {
		$output .= "\n---\n\n";
		$content = file_get_contents($file);
		$content = preg_replace('/^(#+) (.*?)$/m', '##$1 $2', $content);
		$content = preg_replace('/^(#{7,}) (.*?)$/m', '**$2**', $content);
	}

	echo $output;
}
