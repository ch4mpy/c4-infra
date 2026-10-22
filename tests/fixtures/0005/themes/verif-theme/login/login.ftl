<#-- tests/0005-themes.sh: the test replaces @STAMP@ with each registration's stamp -->
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>verif-theme</title>
  <link rel="stylesheet" href="${url.resourcesPath}/css/verif.css">
</head>
<body>
  <p id="stamp">VERIF-STAMP-@STAMP@</p>
  <p id="resources">RESOURCES=${url.resourcesPath}</p>
</body>
</html>
