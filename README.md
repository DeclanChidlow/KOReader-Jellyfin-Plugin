<div align="center">
<h1>
  KOReader Jellyfin Plugin
  
  [![Stars](https://img.shields.io/github/stars/DeclanChidlow/KOReader-Jellyfin-Plugin?style=flat-square&logoColor=white)](https://github.com/DeclanChidlow/KOReader-Jellyfin-Plugin/stargazers)
  [![Forks](https://img.shields.io/github/forks/DeclanChidlow/KOReader-Jellyfin-Plugin?style=flat-square&logoColor=white)](https://github.com/DeclanChidlow/KOReader-Jellyfin-Plugin/network/members)
  [![Pull Requests](https://img.shields.io/github/issues-pr/DeclanChidlow/KOReader-Jellyfin-Plugin?style=flat-square&logoColor=white)](https://github.com/DeclanChidlow/KOReader-Jellyfin-Plugin/pulls)
  [![Issues](https://img.shields.io/github/issues/DeclanChidlow/KOReader-Jellyfin-Plugin?style=flat-square&logoColor=white)](https://github.com/DeclanChidlow/KOReader-Jellyfin-Plugin/issues)
  [![Contributors](https://img.shields.io/github/contributors/DeclanChidlow/KOReader-Jellyfin-Plugin?style=flat-square&logoColor=white)](https://github.com/DeclanChidlow/KOReader-Jellyfin-Plugin/graphs/contributors)
  [![Licence](https://img.shields.io/github/license/DeclanChidlow/KOReader-Jellyfin-Plugin?style=flat-square&logoColor=white)](https://github.com/DeclanChidlow/KOReader-Jellyfin-Plugin/blob/main/LICENCE)
</h1>
A plugin for KOReader adding support for reading books from Jellyfin
</div>
<br/>

This is a simple [KOReader](https://koreader.rocks) plugin that allows you to authenticate with your [Jellyfin](https://jellyfin.org) server, browse books, download them, and mark them as read.

This plugin isn't endorsed by Jellyfin or KOReader.

## Features

- **Server Configuration**: Connect to your own Jellyfin server
- **Authentication**:
  - Login with username and password
  - Login with Quick Connect
- **Browse Books**: View all books in your Jellyfin libraries
- **Download Books**: Download books directly to your device
- **Mark as Read/Unread**: Update your reading status in Jellyfin

## Installation

1. [Download the latest version](https://github.com/DeclanChidlow/KOReader-Jellyfin-Plugin/releases/latest).
2. Extract the downloaded `.zip` and place it in your KOReader plugins folder: `koreader/plugins/jellyfin.koplugin/`.
3. Restart KOReader.

## Usage

### Login

1. Navigate to tools (🛠️) in KOReader, then find and open 'Jellyfin'. It might be on the second page.
2. Select 'Configure Server', enter your server address (with protocol), and press 'Save'.
3. Select 'Login' and authenticate via either username and password or Quick Connect.

### Browse and Download Books

1. In the Jellyfin plugin's menu under tools, select 'Browse Books'.
2. Select a library.
3. Choose a book.
4. Select 'Download' to download the book.
5. You'll be prompted to open the book immediately or find it later in your downloads folder (`koreader/books/`).

### Mark a Book as Read/Unread

1. In the Jellyfin plugin's menu under tools, select 'Browse Books'.
2. Select a library.
3. Choose a book.
4. Select 'Mark as Read' or 'Mark as Unread'.
5. The status will be updated on your Jellyfin server.
