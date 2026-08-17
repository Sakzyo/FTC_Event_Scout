class Event():
    def __init__(self):
        self.matches = []
        self.teams = []
        self.scores = []
        self.teleop_scores = []
        self.auto_scores = []
        self.endgame_scores = []
    def add_match(self, match, score, teleop_score, auto_score, endgame_score):
        self.matches.append(match)
        self.scores.append(score)
        self.teleop_scores.append(teleop_score)
        self.auto_scores.append(auto_score)
        self.endgame_scores.append(endgame_score)
    def add_team(self, team):
        self.teams.append(team)
    def get_matches(self):
        return self.matches
    def get_teams(self):
        return self.teams
    def get_scores(self):
        return self.scores
    def get_teleop_scores(self):
        return self.teleop_scores
    def get_auto_scores(self):
        return self.auto_scores
    def get_endgame_scores(self):
        return self.endgame_scores
