import cgi
import os

from google.appengine.ext import db
from google.appengine.ext import webapp
from google.appengine.ext.webapp import template
from google.appengine.ext.webapp.util import run_wsgi_app
from google.appengine.api import images

class Profile(db.Model):
    rfid = db.StringProperty()
    name = db.StringProperty()
    bio = db.StringProperty(multiline=True)
    photo = db.BlobProperty()

class AccessHistory(db.Model):
    profile = db.StringProperty()
    accessed = db.DateTimeProperty(auto_now_add=True)

class MainPage(webapp.RequestHandler):
    """ Display available profiles, link to other functions. """
    def get(self):
        profiles = db.GqlQuery("select * "
                               "from Profile "
                               "order by name")
        template_values = {'profiles': profiles,
                           'profiles_empty': profiles.count() == 0}

        path = os.path.join(os.path.dirname(__file__), 'index.html')
        self.response.out.write(template.render(path, template_values))

class Config(webapp.RequestHandler):
    """ For to add/overwrite profile and logic to handle post from it. """
    def get(self):
        profile_key = self.request.get('key')
        if len(profile_key) == 0:
            template_values = {}
        else:
            profile = db.get(profile_key)
            template_values = { 'profile':profile }
        path = os.path.join(os.path.dirname(__file__), 'add_form.html')
        self.response.out.write(template.render(path, template_values))

    def post(self):
        key = self.request.get('key')
        if len(key) == 0:
            profile = Profile()
        else:
            profile = db.get(key)
            if profile is None:
                profile = Profile()
        profile.name = self.request.get('name')
        photo = self.request.get('photo')
        if len(photo) > 0:
            photo = db.Blob(images.resize(photo, 128, 128))
            profile.photo = photo
        profile.rfid =  self.request.get('rfid')
        profile.bio = self.request.get('bio')
        profile.put()
        profile = db.get(profile.key())
        template_values = { 'name': profile.name,
                            'rfid': profile.rfid }
        path = os.path.join(os.path.dirname(__file__), 'save_receipt.html')
        self.response.out.write(template.render(path, template_values))

class Delete(webapp.RequestHandler):
    def get(self):
        profile_key = self.request.get('key')
        db.delete(profile_key)
        self.redirect("/")

class ViewProfile(webapp.RequestHandler):
    def get(self):
        profile_key = self.request.get('key')
        profile = db.get(profile_key)
        template_values = { 'profile': profile }
        path = os.path.join(os.path.dirname(__file__), 'view_profile.html')
        self.response.out.write(template.render(path, template_values))

class ViewLast(webapp.RequestHandler):
    def get(self):
        access_history = db.GqlQuery("select * "
                                     "from AccessHistory "
                                     "order by accessed desc "
                                     "limit 1")
        if access_history.count() == 0:
            self.response.out.write("No last access.")
            return
        profile_key = access_history[0].profile
        profile = db.get(profile_key)
        template_values = { 'profile': profile,
                            'accessed': access_history[0].accessed }
        path = os.path.join(os.path.dirname(__file__), 'view_profile.html')
        self.response.out.write(template.render(path, template_values))

class Photo(webapp.RequestHandler):
    def get(self):
      profile = db.get(self.request.get("key"))
      if profile.photo:
          self.response.headers['Content-Type'] = "image/png"
          self.response.out.write(profile.photo)
      else:
          self.error(404)

class Access(webapp.RequestHandler):
    def post(self):
        rfid = self.request.get('id')
        self.response.out.write(self._access(rfid))

    def get(self):
        rfid = self.request.get('id')
        self.response.out.write(self._access(rfid))

    def _access(self, rfid):
        profiles = db.GqlQuery("select * "
                          "from Profile "
                          "where rfid = :1",
                          rfid)
        if profiles.count() >= 1:
            # this isn't going to work so well if there are duplicate rfids
            # which this application does not prevent
            profile = profiles[0]
            access_entry = AccessHistory()
            access_entry.profile = str(profile.key())
            access_entry.put()
            return 'OK'
        else:
            return 'REJECTED'

application = webapp.WSGIApplication(
                                     [('/', MainPage),
                                      ('/profile', ViewProfile),
                                      ('/view', ViewLast),
                                      ('/delete', Delete),
                                      ('/config', Config),
                                      ('/photo', Photo),
                                      ('/rfid', Access)],
                                     debug=True)

def main():
    run_wsgi_app(application)

if __name__ == "__main__":
    main()
