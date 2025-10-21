# Hipertext
**Hipertext** is a static site generator (SSG) written in Swift. It aims to be opinative and provides a zero config approach to SSG.

>[!WARNING]
> Hipertext is still in active development. Until version 1.0 is released, it is **not recommended** for production use.

## Usage
```sh
hx init   # Create a new project
hx build  # Generate the website
hx serve  # Preview locally
```

## Structure
```sh
content/   # Your words
static/    # Your assets
styles/    # Your aesthetic
templates/ # Your structure
public/    # Your website
```

## Templates
```html
<!DOCTYPE html>
<html>
<head>
    <title>{{ title }}</title>
</head>
<body>
    {{{ content }}}
</body>
</html>
```

## Content 
```md
--- 
template: page.html
title: A great article
---

# Heading

Content
```

## License
This project is licensed under GNU GPLv3 License. Check [LICENSE](LICENSE) for more information.
